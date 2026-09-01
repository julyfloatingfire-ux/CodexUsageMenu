import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    var canRevealExit: (() -> Bool)?
    var onShortClick: (() -> Void)?
    private var pressScreenLocation: NSPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where canRevealExit?() == true:
            // 拖动窗口后 locationInWindow 会随窗口坐标一起变化，必须记录全局屏幕坐标。
            pressScreenLocation = NSEvent.mouseLocation
        case .leftMouseUp:
            let shouldReveal = canRevealExit?() == true && pressScreenLocation.map {
                hypot(NSEvent.mouseLocation.x - $0.x, NSEvent.mouseLocation.y - $0.y) < 4
            } == true
            pressScreenLocation = nil
            super.sendEvent(event)
            if shouldReveal { onShortClick?() }
            return
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    private enum Layout { static let square = NSSize(width: 128, height: 128) }

    private let store = UsageStore()
    private let presentation: FloatingPresentation
    private let panel: FloatingPanel
    private var activityTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var missingCodexChecks = 0
    private let positionKey = "floatingWindowOrigin"
    private let pinnedKey = "floatingWindowPinned"

    override init() {
        presentation = FloatingPresentation(
            isPinned: UserDefaults.standard.object(forKey: "floatingWindowPinned") as? Bool ?? true
        )
        panel = FloatingPanel(
            contentRect: Self.initialFrame(size: Layout.square),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 默认置顶；用户可在方框内切换为普通窗口层级。
        updateWindowLevel(isPinned: presentation.isPinned)
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.canRevealExit = { [weak presentation] in !(presentation?.showsExit ?? false) }
        panel.onShortClick = { [weak self] in self?.presentation.showsExit = true }
        panel.contentViewController = NSHostingController(
            rootView: UsageSquareView(
                store: store,
                presentation: presentation,
                togglePinned: { [weak self] in self?.togglePinned() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncCodexVisibility() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncCodexVisibility(hideImmediately: true) }
            }
        ]
        syncCodexVisibility()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncCodexVisibility() }
        }
    }

    func shutdown() {
        activityTimer?.invalidate()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        panel.orderOut(nil)
        store.shutdown()
    }

    func windowDidMove(_ notification: Notification) {
        constrainPanelToScreen()
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: positionKey)
    }

    private func syncCodexVisibility(hideImmediately: Bool = false) {
        if isCodexDesktopRunning {
            missingCodexChecks = 0
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            missingCodexChecks += 1
            guard (hideImmediately || missingCodexChecks >= 3), panel.isVisible else { return }
            presentation.showsExit = false
            panel.orderOut(nil)
        }
    }

    private func togglePinned() {
        presentation.isPinned.toggle()
        UserDefaults.standard.set(presentation.isPinned, forKey: pinnedKey)
        updateWindowLevel(isPinned: presentation.isPinned)
    }

    private func updateWindowLevel(isPinned: Bool) {
        if isPinned {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            panel.level = .normal
            panel.collectionBehavior = [.stationary]
        }
    }

    private var isCodexDesktopRunning: Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty { return true }
        return NSWorkspace.shared.runningApplications.contains { app in
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let identifier = app.bundleIdentifier?.lowercased() ?? ""
            return name == "codex" || identifier.contains(".codex")
        }
    }

    private func constrainPanelToScreen() {
        let visible = screen(for: panel.frame).visibleFrame
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func screen(for frame: NSRect) -> NSScreen {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) { return screen }
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private static func initialFrame(size: NSSize) -> NSRect {
        if let saved = UserDefaults.standard.array(forKey: "floatingWindowOrigin") as? [CGFloat], saved.count == 2 {
            let frame = NSRect(origin: NSPoint(x: saved[0], y: saved[1]), size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return frame }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.maxX - size.width - 34, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }
}
