import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingPresentation: ObservableObject {
    @Published var isExpanded = false
}

struct FloatingUsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var presentation: FloatingPresentation
    let hoverChanged: (Bool) -> Void
    let refresh: () -> Void
    let quit: () -> Void

    var body: some View {
        // 外层始终存在，不能随圆球/面板切换而替换，否则 onHover 会被误触发为移出。
        ZStack {
            compactView
                .opacity(presentation.isExpanded ? 0 : 1)
                .allowsHitTesting(!presentation.isExpanded)
            expandedView
                .opacity(presentation.isExpanded ? 1 : 0)
                .allowsHitTesting(presentation.isExpanded)
        }
        .frame(
            width: presentation.isExpanded ? 284 : 62,
            height: presentation.isExpanded ? 282 : 62
        )
        .clipped()
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .animation(.easeInOut(duration: 0.16), value: presentation.isExpanded)
    }

    private var compactView: some View {
        let usage = store.selected
        return ZStack {
            Circle().fill(.thinMaterial)
            // strokeBorder 向圆内绘制，避免悬浮窗裁剪掉外侧半个描边。
            Circle().strokeBorder(Color.blue.opacity(0.8), lineWidth: 2)
            VStack(spacing: 0) {
                Text(store.selectedWindow.shortTitle.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(usage.map { "\($0.remainingPercent)%" } ?? "--")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)
        }
        .frame(width: 62, height: 62)
    }

    private var expandedView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.blue.opacity(0.65), lineWidth: 1)

            VStack(spacing: 7) {
                metric("5小时·剩余用量", store.snapshot?.fiveHour, cycle: false)
                Divider()
                metric("1周·剩余用量", store.snapshot?.weekly, cycle: true)
                Divider()
                Picker("悬浮球显示", selection: $store.selectedWindow) {
                    ForEach(MenuWindow.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)

                Toggle("开机时自动启动", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Toggle("5小时用量恢复后发送提醒", isOn: Binding(
                    get: { store.notifyOnFiveHourReset },
                    set: { store.setNotificationEnabled($0) }
                ))

                HStack {
                    Button("手动刷新") { refresh() }
                    Spacer()
                    Button("退出") { quit() }
                }
            }
            .font(.system(size: NSFont.systemFontSize))
            .padding(13)
        }
        .frame(width: 284, height: 282)
    }

    @ViewBuilder
    private func metric(_ title: String, _ usage: UsageWindow?, cycle: Bool) -> some View {
        if let usage {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).fontWeight(.medium)
                    Spacer()
                    Text(usage.resetText(now: store.now)).foregroundStyle(.secondary)
                }
                progress(Double(usage.remainingPercent) / 100, "\(usage.remainingPercent)%")
                if cycle {
                    HStack {
                        Text("1周·周期剩余时间")
                        Spacer()
                        Text(usage.remainingTimeText(now: store.now)).foregroundStyle(.secondary)
                    }
                    progress(usage.remainingCyclePercent(now: store.now), "\(Int(usage.remainingCyclePercent(now: store.now) * 100))%")
                }
            }
        } else {
            HStack { Text(title); Spacer(); Text("正在读取…").foregroundStyle(.secondary) }
        }
    }

    private func progress(_ fraction: Double, _ text: String) -> some View {
        HStack(spacing: 7) {
            ProgressView(value: fraction).tint(.blue).scaleEffect(y: 0.78)
            Text(text).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
    }
}
