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
            VStack(spacing: 8) {
                metric("5h", store.snapshot?.fiveHour, showsReset: true)
                Divider().padding(.horizontal, 13)
                metric("1周", store.snapshot?.weekly, showsReset: false)
            }
            .padding(.horizontal, 13)

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

    private func metric(_ title: String, _ usage: UsageWindow?, showsReset: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(usage.map { "剩余 \($0.remainingPercent)%" } ?? "读取中")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            if showsReset {
                Text(usage?.resetText(now: store.now) ?? "恢复时间未知")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .font(.system(size: 10))
    }
}
