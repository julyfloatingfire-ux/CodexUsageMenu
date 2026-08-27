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
    private var deferredStatusTitle: String?
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
        // 左键仅用于正常的状态栏交互；只有右键释放才会把预览固定为可操作窗口。
        button.sendAction(on: [.rightMouseUp])
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        button.addTrackingArea(area)

        store.$snapshot.combineLatest(store.$selectedWindow).sink { [weak self, weak button] snapshot, choice in
            let value = snapshot?.window(choice).map { "\($0.remainingPercent)%" } ?? "--"
            let title = " \(choice.shortTitle) \(value)"
            guard let self else { return }
            // 弹窗显示期间不改变状态栏项宽度，以免 Picker 切换时重算锚点位置。
            if self.popover.isShown {
                self.deferredStatusTitle = title
            } else {
                button?.title = title
            }
        }.store(in: &bag)

        // 不使用 transient，避免系统在点击状态栏图标时抢先关闭预览窗口。
        // 所有关闭都由 evaluatePointerLocation() 统一处理。
        popover.behavior = .applicationDefined
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
        // 右键只负责进入固定态；固定后不因再次右键关闭。
        if popover.isShown {
            if !pinned { setPinned() }
        } else {
            show(pinned: true)
        }
    }

    private func setPinned() {
        pinned = true
        presentation.isInteractive = true
        popover.behavior = .applicationDefined
        closeJob?.cancel()
    }
    private func show(pinned: Bool) {
        guard let button = item.button, pointerOverButton || pinned else { return }
        self.pinned = pinned
        presentation.isInteractive = pinned
        popover.behavior = .applicationDefined
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
        popover.behavior = .applicationDefined
        popover.performClose(nil)
        applyDeferredStatusTitle()
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
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown]
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            DispatchQueue.main.async { self?.evaluatePointerLocation(for: event) }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.evaluatePointerLocation(for: event)
            return event
        }
    }

    private func evaluatePointerLocation(for event: NSEvent? = nil) {
        guard popover.isShown else { return }
        // 分段选择器等控件的事件属于 popover window；即使坐标更新尚未完成，也不能误判为外部点击。
        if let event, event.window === popover.contentViewController?.view.window {
            closeJob?.cancel()
            closeJob = nil
            return
        }
        guard !pointerOverButton && !pointerOverPopover else {
            closeJob?.cancel()
            closeJob = nil
            return
        }
        if pinned {
            // 固定态忽略鼠标移动；仅在窗口外实际点击时关闭。
            if let event, event.type == .leftMouseDown || event.type == .rightMouseDown {
                close()
            }
        } else {
            // 预览态离开图标和面板即收起。
            close()
        }
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
    private func applyDeferredStatusTitle() {
        guard let title = deferredStatusTitle else { return }
        item.button?.title = title
        deferredStatusTitle = nil
    }
    func popoverDidClose(_ notification: Notification) {
        timer?.invalidate()
        pinned = false
        presentation.isInteractive = false
        popover.behavior = .applicationDefined
        applyDeferredStatusTitle()
    }
}
