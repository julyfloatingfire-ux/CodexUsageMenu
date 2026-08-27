import SwiftUI

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Codex Usage", systemImage: "hourglass")
                    .font(.headline)
                Spacer()
                Text("自动更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if let snapshot = store.snapshot {
                window("5 小时窗口", snapshot.fiveHour, showsCycleTime: false)
                Divider().padding(.leading, 14)
                window("一周窗口", snapshot.weekly, showsCycleTime: true)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(store.errorText ?? "正在读取 Codex 用量…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
            Divider()
            VStack(spacing: 10) {
                Picker("顶部显示", selection: $store.selectedWindow) {
                    ForEach(MenuWindow.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("退出") { NSApplication.shared.terminate(nil) }
                    Spacer()
                    Button("关闭") { close() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
        }
        .frame(width: 350)
    }

    @ViewBuilder
    private func window(_ title: String, _ usage: UsageWindow?, showsCycleTime: Bool) -> some View {
        if let usage {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).fontWeight(.medium)
                    Spacer()
                    Text(usage.resetText(now: store.now)).font(.caption).foregroundStyle(.secondary)
                }
                progress("剩余用量", "\(usage.remainingPercent)%", Double(usage.remainingPercent) / 100, .blue)
                if showsCycleTime {
                    let cycleTime = usage.remainingCyclePercent(now: store.now)
                    progress("本周期剩余时间", "\(Int(cycleTime * 100))% · \(usage.remainingTimeText(now: store.now))", cycleTime, .purple)
                }
            }
            .padding(14)
        } else {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text("暂不可用").foregroundStyle(.secondary) }
                .padding(14)
        }
    }

    private func progress(_ name: String, _ value: String, _ fraction: Double, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            HStack { Text(name); Spacer(); Text(value).fontWeight(.medium).monospacedDigit() }
                .font(.system(size: 13))
            ProgressView(value: fraction).tint(tint)
        }
    }
}
