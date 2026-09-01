import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let ball = NSSize(width: 112, height: 112)
    }

    private let store = UsageStore()
    private let panel: FloatingPanel
    private var activityTimer: Timer?
    private var missingCodexChecks = 0
    private let positionKey = "floatingWindowOrigin"

    override init() {
        panel = FloatingPanel(
            contentRect: Self.initialFrame(size: Layout.ball),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 原生窗口拖动：只有按住并移动才会改变圆球位置。
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: UsageBallView(store: store))

        syncCodexVisibility()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncCodexVisibility() }
        }
    }

    func shutdown() {
        activityTimer?.invalidate()
        panel.orderOut(nil)
        store.shutdown()
    }

    func windowDidMove(_ notification: Notification) {
        constrainPanelToScreen()
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: positionKey)
    }

    private func syncCodexVisibility() {
        if isCodexDesktopRunning {
            missingCodexChecks = 0
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            missingCodexChecks += 1
            guard missingCodexChecks >= 3, panel.isVisible else { return }
            panel.orderOut(nil)
        }
    }

    private var isCodexDesktopRunning: Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty {
            return true
        }
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
