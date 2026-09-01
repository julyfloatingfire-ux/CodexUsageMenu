import AppKit
import Combine
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let compact = NSSize(width: 62, height: 62)
        static let expanded = NSSize(width: 284, height: 282)
    }

    private let store = UsageStore()
    private let presentation = FloatingPresentation()
    private let panel: FloatingPanel
    private var activityTimer: Timer?
    private var bag = Set<AnyCancellable>()
    private var missingCodexChecks = 0
    private let positionKey = "floatingWindowOrigin"

    override init() {
        let initialFrame = Self.initialFrame(size: Layout.compact)
        panel = FloatingPanel(
            contentRect: initialFrame,
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
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: FloatingUsageView(
                store: store,
                presentation: presentation,
                refresh: { self.store.refresh() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )

        presentation.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.resizePanel(expanded: expanded) }
            .store(in: &bag)

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
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: positionKey)
    }

    private func syncCodexVisibility() {
        if isCodexDesktopRunning {
            missingCodexChecks = 0
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            // NSWorkspace 偶尔会在应用切换时漏掉一次快照；连续三次未命中才隐藏。
            missingCodexChecks += 1
            guard missingCodexChecks >= 3, panel.isVisible else { return }
            presentation.isExpanded = false
            panel.orderOut(nil)
        }
    }

    private var isCodexDesktopRunning: Bool {
        // 当前桌面版 Codex 的宿主显示名是 ChatGPT，但 bundle identifier 为 com.openai.codex。
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty {
            return true
        }
        return NSWorkspace.shared.runningApplications.contains { app in
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let identifier = app.bundleIdentifier?.lowercased() ?? ""
            return name == "codex" || identifier.contains(".codex")
        }
    }

    private func resizePanel(expanded: Bool) {
        let target = expanded ? Layout.expanded : Layout.compact
        let current = panel.frame
        let center = NSPoint(x: current.midX, y: current.midY)
        var frame = NSRect(
            x: center.x - target.width / 2,
            y: center.y - target.height / 2,
            width: target.width,
            height: target.height
        )
        let visibleFrame = screenForCurrentPanel.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        panel.setFrame(frame, display: true, animate: true)
    }

    private var screenForCurrentPanel: NSScreen {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) {
            return screen
        }
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) {
            return screen
        }
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
