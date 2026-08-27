import SwiftUI

struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, minHeight: 105)
            }
            Divider()
            HStack(spacing: 8) {
                Text("顶部显示")
                    .font(.footnote)
                Picker("顶部显示", selection: $store.selectedWindow) {
                    ForEach(MenuWindow.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 9)
            .padding(.top, 7)

            Toggle("登录时自动启动", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .font(.footnote)
            .padding(.horizontal, 9)
            .padding(.bottom, 7)
        }
        .frame(width: 230)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func window(_ title: String, _ usage: UsageWindow?, showsCycleTime: Bool) -> some View {
        if let usage {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.footnote.weight(.medium))
                    Spacer()
                    Text(usage.resetText(now: store.now)).font(.caption).foregroundStyle(.secondary)
                }
                progress("剩余用量", "\(usage.remainingPercent)%", Double(usage.remainingPercent) / 100, .blue)
                if showsCycleTime {
                    let cycleTime = usage.remainingCyclePercent(now: store.now)
                    progress("本周期剩余时间", "\(Int(cycleTime * 100))% · \(usage.remainingTimeText(now: store.now))", cycleTime, .blue)
                }
            }
            .padding(10)
        } else {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text("暂不可用").foregroundStyle(.secondary) }
                .padding(10)
        }
    }

    private func progress(_ name: String, _ value: String, _ fraction: Double, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(value).fontWeight(.medium).monospacedDigit() }
                .font(.system(size: 12.5))
            ProgressView(value: fraction)
                .tint(tint)
                .scaleEffect(y: 0.72)
        }
    }
}
