import AppKit
import SwiftUI

struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = store.snapshot {
                window("5小时·剩余用量", snapshot.fiveHour, showsCycleTime: false)
                Divider().padding(.leading, 14)
                window("1周·剩余用量", snapshot.weekly, showsCycleTime: true)
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
                    .font(interfaceFont)
                Picker("顶部显示", selection: $store.selectedWindow) {
                    ForEach(MenuWindow.allCases) { item in Text(item.title).tag(item) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.top, 7)

            Toggle("开机时自动启动", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .font(interfaceFont)
            .padding(.horizontal, 9)

            Toggle("5小时刷新后提醒", isOn: Binding(
                get: { store.notifyOnFiveHourReset },
                set: { store.setNotificationEnabled($0) }
            ))
            .font(interfaceFont)
            .padding(.horizontal, 9)
            .padding(.bottom, 7)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func window(_ title: String, _ usage: UsageWindow?, showsCycleTime: Bool) -> some View {
        if let usage {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(interfaceFont.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(usage.resetText(now: store.now))
                        .font(interfaceFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                progress(Double(usage.remainingPercent) / 100, "\(usage.remainingPercent)%")
                if showsCycleTime {
                    let cycleTime = usage.remainingCyclePercent(now: store.now)
                    Text("1周·周期剩余时间 · \(usage.remainingTimeText(now: store.now))")
                        .font(interfaceFont)
                        .lineLimit(1)
                    progress(cycleTime, "\(Int(cycleTime * 100))%")
                }
            }
            .padding(10)
        } else {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text("暂不可用").foregroundStyle(.secondary) }
                .padding(10)
        }
    }

    private func progress(_ fraction: Double, _ percent: String) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: fraction)
                .tint(.blue)
                .scaleEffect(y: 0.8)
            Text(percent)
                .font(interfaceFont.weight(.medium))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var interfaceFont: Font { .system(size: NSFont.systemFontSize) }
}
