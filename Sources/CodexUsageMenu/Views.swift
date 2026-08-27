import AppKit
import Combine
import SwiftUI

@MainActor
final class PopoverPresentation: ObservableObject {
    @Published var isInteractive = false
}

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var presentation: PopoverPresentation
    let refresh: () -> Void
    let quit: () -> Void

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
            HStack(spacing: 6) {
                Text("顶部显示")
                    .font(interfaceFont)
                Picker("顶部显示", selection: $store.selectedWindow) {
                    ForEach(MenuWindow.allCases) { item in Text(item.title).tag(item) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)

            Toggle("开机时自动启动", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .font(interfaceFont)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 3)

            Toggle("5小时用量恢复后发送提醒", isOn: Binding(
                get: { store.notifyOnFiveHourReset },
                set: { store.setNotificationEnabled($0) }
            ))
            .font(interfaceFont)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            HStack {
                Button("手动刷新") { refresh() }
                Spacer()
                Button("退出") { quit() }
            }
            .font(interfaceFont)
            .padding(.horizontal, 8)
            .padding(.bottom, 5)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .tint(presentation.isInteractive ? .blue : .gray)
        .disabled(!presentation.isInteractive)
        .background(presentation.isInteractive ? Color.blue.opacity(0.12) : Color.gray.opacity(0.14))
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
                    HStack {
                        Text("1周·周期剩余时间")
                            .font(interfaceFont)
                            .lineLimit(1)
                        Spacer()
                        Text(usage.remainingTimeText(now: store.now))
                            .font(interfaceFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    progress(cycleTime, "\(Int(cycleTime * 100))%")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        } else {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text("暂不可用").foregroundStyle(.secondary) }
                .padding(8)
        }
    }

    private func progress(_ fraction: Double, _ percent: String) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: fraction)
                .tint(presentation.isInteractive ? .blue : .gray)
                .scaleEffect(y: 0.8)
            Text(percent)
                .font(interfaceFont.weight(.medium))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var interfaceFont: Font { .system(size: NSFont.systemFontSize) }
}
