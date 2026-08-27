import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSResponder, NSPopoverDelegate {
    private let store = UsageStore()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var closeJob: DispatchWorkItem?
    private var timer: Timer?
    private var pinned = false
    private var bag = Set<AnyCancellable>()

    override init() {
        super.init()
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
        popover.contentSize = NSSize(width: 350, height: 380)
        popover.contentViewController = NSHostingController(rootView: UsagePopover(store: store, close: { [weak self] in self?.close() }))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func shutdown() { timer?.invalidate(); store.shutdown() }

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

    private func setPinned() { pinned = true; closeJob?.cancel() }
    private func show(pinned: Bool) {
        guard let button = item.button, pointerOverButton || pinned else { return }
        self.pinned = pinned
        closeJob?.cancel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startMonitor()
    }
    private func close() { closeJob?.cancel(); timer?.invalidate(); pinned = false; popover.performClose(nil) }
    private func startMonitor() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHover() }
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
    func popoverDidClose(_ notification: Notification) { timer?.invalidate(); pinned = false }
}
