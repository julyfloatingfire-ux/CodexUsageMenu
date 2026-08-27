import Combine
import Foundation
import ServiceManagement

enum MenuWindow: String, CaseIterable, Identifiable {
    case fiveHour, weekly
    var id: String { rawValue }
    var title: String { self == .fiveHour ? "5 小时" : "一周" }
    var shortTitle: String { self == .fiveHour ? "5h" : "7d" }
}

struct UsageWindow: Equatable {
    let usedPercent: Int
    let durationMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

    func remainingCyclePercent(now: Date) -> Double {
        guard let resetsAt else { return 0 }
        let duration = Double(durationMinutes * 60)
        return min(1, max(0, resetsAt.timeIntervalSince(now) / duration))
    }

    func resetText(now: Date) -> String {
        guard let resetsAt else { return "恢复时间未知" }
        if Calendar.current.isDateInToday(resetsAt) {
            return resetsAt.formatted(date: .omitted, time: .shortened) + " 恢复"
        }
        return resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()) + " 恢复"
    }

    func remainingTimeText(now: Date) -> String {
        guard let resetsAt else { return "恢复时间未知" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        if seconds == 0 { return "正在同步新周期" }
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "还剩 \(days)天\(hours)小时" }
        if hours > 0 { return "还剩 \(hours)小时\(minutes)分" }
        return "还剩 \(max(1, minutes))分钟"
    }
}

struct UsageSnapshot: Equatable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    func window(_ choice: MenuWindow) -> UsageWindow? { choice == .fiveHour ? fiveHour : weekly }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var errorText: String?
    @Published private(set) var launchAtLogin: Bool
    @Published var selectedWindow: MenuWindow {
        didSet { UserDefaults.standard.set(selectedWindow.rawValue, forKey: "menuWindow") }
    }
    @Published private(set) var now = Date.now

    private let server = CodexServer()
    private var clockTimer: Timer?
    private var refreshTimer: Timer?

    init() {
        selectedWindow = MenuWindow(rawValue: UserDefaults.standard.string(forKey: "menuWindow") ?? "") ?? .fiveHour
        launchAtLogin = SMAppService.mainApp.status == .enabled
        server.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.snapshot = snapshot; self?.errorText = nil }
        }
        server.onError = { [weak self] message in
            Task { @MainActor in self?.errorText = message }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = .now }
        }
        // Codex app-server 会推送 account/rateLimits/updated；每分钟轮询仅作断线兜底。
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.server.refresh()
        }
        server.start()
    }

    var selected: UsageWindow? { snapshot?.window(selectedWindow) }
    func refresh() { server.refresh() }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorText = "无法更新登录启动：\(error.localizedDescription)"
        }
    }
    func shutdown() { clockTimer?.invalidate(); refreshTimer?.invalidate(); server.stop() }
}

final class CodexServer: @unchecked Sendable {
    var onSnapshot: (@Sendable (UsageSnapshot) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "CodexUsageMenu.server")
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var initialized = false
    private var nextID = 1

    func start() { queue.async { [weak self] in self?.startLocked() } }
    func stop() { queue.async { [weak self] in self?.process?.terminate(); self?.process = nil } }
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.process?.isRunning == true else { self.startLocked(); return }
            guard self.initialized else { return }
            self.send("account/rateLimits/read", NSNull())
        }
    }

    private func startLocked() {
        guard process?.isRunning != true else { return }
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            onError?("未找到 Codex CLI")
            return
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.queue.async { self?.consume(data) } }
        }
        process.terminationHandler = { [weak self] _ in self?.onError?("Codex 服务已停止") }
        do {
            try process.run()
            self.process = process
            self.input = input
            initialized = false
            send("initialize", [
                "clientInfo": ["name": "codex-usage-menu", "title": "Codex Usage Menu", "version": "1.0"],
                "capabilities": ["experimentalApi": true]
            ])
        } catch { onError?("无法启动 Codex：\(error.localizedDescription)") }
    }

    private func send(_ method: String, _ params: Any) {
        guard let input else { return }
        let payload: [String: Any] = ["id": nextID, "method": method, "params": params]
        nextID += 1
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(10)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let index = buffer.firstIndex(of: 10) {
            let line = buffer[..<index]
            buffer.removeSubrange(...index)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if !initialized, object["id"] != nil, object["result"] != nil {
                initialized = true
                send("account/rateLimits/read", NSNull())
                continue
            }
            if let error = object["error"] as? [String: Any] {
                onError?(error["message"] as? String ?? "Codex 返回错误")
                continue
            }
            let payload = (object["result"] as? [String: Any]) ?? (object["params"] as? [String: Any])
            if let payload, let snapshot = parse(payload) { onSnapshot?(snapshot) }
        }
    }

    private func parse(_ payload: [String: Any]) -> UsageSnapshot? {
        let limits = (payload["rateLimits"] as? [String: Any])
            ?? ((payload["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
            ?? payload
        let windows = [limits["primary"], limits["secondary"]]
            .compactMap { $0 as? [String: Any] }
            .compactMap { object -> UsageWindow? in
                guard let used = object["usedPercent"] as? Int,
                      let duration = object["windowDurationMins"] as? Int else { return nil }
                let timestamp = object["resetsAt"] as? TimeInterval
                return UsageWindow(usedPercent: used, durationMinutes: duration, resetsAt: timestamp.map(Date.init(timeIntervalSince1970:)))
            }
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(
            fiveHour: windows.first { $0.durationMinutes == 300 },
            weekly: windows.first { $0.durationMinutes == 10_080 }
        )
    }
}
