import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSResponder, NSPopoverDelegate {
    private let store = UsageStore()
    private let presentation = PopoverPresentation()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var closeJob: DispatchWorkItem?
    private var timer: Timer?
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var pinned = false
    private var bag = Set<AnyCancellable>()

    override init() {
        super.init()
        item.autosaveName = "com.floatingfire.CodexUsageMenu.statusItem"
        item.isVisible = true
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Codex Usage")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp])
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        button.addTrackingArea(area)

        store.$snapshot.combineLatest(store.$selectedWindow).sink { [weak button] snapshot, choice in
            let value = snapshot?.window(choice).map { "\($0.remainingPercent)%" } ?? "--"
            button?.title = " \(choice.shortTitle) \(value)"
        }.store(in: &bag)

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.contentViewController = NSHostingController(
            rootView: UsagePopover(
                store: store,
                presentation: presentation,
                refresh: { self.store.refresh() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )
        startPointerMonitoring()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func shutdown() {
        timer?.invalidate()
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        store.shutdown()
    }

    override func mouseEntered(with event: NSEvent) {
        closeJob?.cancel()
        if !popover.isShown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.show(pinned: false) }
        }
    }

    override func mouseExited(with event: NSEvent) { scheduleClose() }

    @objc private func clicked() {
        if popover.isShown { pinned ? close() : setPinned() } else { show(pinned: true) }
    }

    private func setPinned() {
        pinned = true
        presentation.isInteractive = true
        closeJob?.cancel()
    }
    private func show(pinned: Bool) {
        guard let button = item.button, pointerOverButton || pinned else { return }
        self.pinned = pinned
        presentation.isInteractive = pinned
        closeJob?.cancel()
        // 以状态栏按钮的内缘为锚点，减少气泡与菜单栏之间的视觉间距。
        let anchor = button.bounds.insetBy(dx: 0, dy: 2)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
        startMonitor()
    }
    private func close() {
        closeJob?.cancel()
        timer?.invalidate()
        pinned = false
        presentation.isInteractive = false
        popover.performClose(nil)
    }
    private func startMonitor() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHover() }
        }
    }

    /// transient popover 对菜单栏状态项的 hover/click 组合并不总能可靠地发出关闭事件，
    /// 因此同时监听本应用和其他应用中的指针事件，统一判断是否已离开图标和面板。
    private func startPointerMonitoring() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown]
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            DispatchQueue.main.async { self?.evaluatePointerLocation() }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.evaluatePointerLocation()
            return event
        }
    }

    private func evaluatePointerLocation() {
        guard popover.isShown else { return }
        guard !pointerOverButton && !pointerOverPopover else {
            closeJob?.cancel()
            closeJob = nil
            return
        }
        // 预览态离开即收起；可操作态点击面板外也由此收起。
        close()
    }

    private func checkHover() {
        guard popover.isShown, !pinned else { return }
        if pointerOverButton || pointerOverPopover { closeJob?.cancel() } else { scheduleClose() }
    }
    private func scheduleClose() {
        guard popover.isShown, !pinned, closeJob == nil else { return }
        let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeJob = nil
            if !self.pointerOverButton && !self.pointerOverPopover { self.close() }
        }
        closeJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: job)
    }
    private var pointerOverButton: Bool { item.button?.window?.frame.contains(NSEvent.mouseLocation) ?? false }
    private var pointerOverPopover: Bool { popover.contentViewController?.view.window?.frame.contains(NSEvent.mouseLocation) ?? false }
    func popoverDidClose(_ notification: Notification) {
        timer?.invalidate()
        pinned = false
        presentation.isInteractive = false
    }
}
