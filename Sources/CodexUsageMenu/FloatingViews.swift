import AppKit
import SwiftUI

struct UsageBallView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(Color.blue.opacity(0.82), lineWidth: 2)
            VStack(spacing: 5) {
                metric("5h", store.snapshot?.fiveHour)
                Divider().padding(.horizontal, 17)
                metric("1周", store.snapshot?.weekly)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 112, height: 112)
        .contentShape(Circle())
    }

    private func metric(_ title: String, _ usage: UsageWindow?) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(usage.map { "剩余 \($0.remainingPercent)%" } ?? "读取中")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Text(usage?.resetText(now: store.now) ?? "恢复时间未知")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(.system(size: 9.5))
    }
}
