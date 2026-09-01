import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingPresentation: ObservableObject {
    @Published var showsExit = false
}

struct UsageSquareView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var presentation: FloatingPresentation
    let quit: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.82), lineWidth: 2)
            VStack(spacing: 5) {
                fiveHourMetric(store.snapshot?.fiveHour)
                Divider().padding(.horizontal, 10)
                weeklyMetrics(store.snapshot?.weekly)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)

            if presentation.showsExit {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.09))
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture { presentation.showsExit = false }
                Button("退出") { quit() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .frame(width: 112, height: 112)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fiveHourMetric(_ usage: UsageWindow?) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text("5h").fontWeight(.semibold)
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
        .font(.system(size: 10))
    }

    @ViewBuilder
    private func weeklyMetrics(_ usage: UsageWindow?) -> some View {
        if let usage {
            let cycle = usage.remainingCyclePercent(now: store.now)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("1周").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Text("剩余 \(usage.remainingPercent)%").fontWeight(.semibold).monospacedDigit()
                }
                bar(Double(usage.remainingPercent) / 100)
                HStack(spacing: 3) {
                    Text("周期 \(Int(cycle * 100))%").monospacedDigit()
                    Spacer(minLength: 0)
                    Text(usage.remainingTimeText(now: store.now))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                bar(cycle)
            }
            .font(.system(size: 9.5))
        } else {
            HStack { Text("1周").fontWeight(.semibold); Spacer(); Text("读取中") }
                .font(.system(size: 10))
        }
    }

    private func bar(_ value: Double) -> some View {
        ProgressView(value: value)
            .tint(.blue)
            .scaleEffect(y: 0.62)
    }
}
