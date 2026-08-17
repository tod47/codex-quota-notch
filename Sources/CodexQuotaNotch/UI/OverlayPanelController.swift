import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private var snapshot: QuotaSnapshot
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var currentAlert: QuotaAlert?
    private var hideWorkItem: DispatchWorkItem?
    private var alertDismissWorkItem: DispatchWorkItem?
    private var activeMode: DisplayMode?

    var onOpenMainWindow: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    init(settingsStore: SettingsStore, snapshot: QuotaSnapshot) {
        self.settingsStore = settingsStore
        self.snapshot = snapshot
        super.init()
    }

    func update(snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
        refreshContent()
    }

    func updateSettings(_ settings: AppSettings) {
        let previousMode = activeMode
        refreshContent()

        switch settings.displayMode {
        case .topPopup:
            activeMode = .topPopup
            if panel?.isVisible == true, previousMode != .topPopup {
                panel?.orderOut(nil)
                onVisibilityChanged?(false)
            }
        case .topPersistent:
            activeMode = .topPersistent
            showPersistent()
        case .floating:
            activeMode = .floating
            showFloating()
        }
    }

    func present(alert: QuotaAlert) {
        currentAlert = alert
        refreshContent()
        alertDismissWorkItem?.cancel()

        switch settingsStore.settings.displayMode {
        case .topPopup:
            showTopPopup(on: screenForCurrentPointer())
        case .topPersistent:
            showPersistent()
        case .floating:
            showFloating()
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentAlert = nil
                self.refreshContent()
                if self.settingsStore.settings.displayMode == .topPopup {
                    self.scheduleHide()
                }
            }
        }
        alertDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func handlePointer(_ point: NSPoint) {
        guard settingsStore.settings.displayMode == .topPopup else { return }
        guard let screen = TopTriggerMonitor.screen(containing: point) else { return }

        let inTrigger = TopTriggerMonitor.triggerRect(for: screen).contains(point)
        let inPanel = panel?.isVisible == true && panel?.frame.contains(point) == true
        if inTrigger || inPanel {
            hideWorkItem?.cancel()
            if inTrigger {
                showTopPopup(on: screen)
            }
        } else if panel?.isVisible == true {
            scheduleHide()
        }
    }

    func showTopPopup(on screen: NSScreen) {
        let panel = makePanelIfNeeded()
        configurePanel(for: .topPopup)
        let frame = topFrame(on: screen)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
        activeMode = .topPopup
    }

    func showPersistent() {
        let panel = makePanelIfNeeded()
        configurePanel(for: .topPersistent)
        panel.setFrame(topFrame(on: screenForCurrentPointer()), display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
        activeMode = .topPersistent
    }

    func showFloating() {
        let panel = makePanelIfNeeded()
        configurePanel(for: .floating)
        let frame = resolvedFloatingFrame()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
        activeMode = .floating
    }

    func hidePopup() {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
        onVisibilityChanged?(false)
    }

    func resetFloatingFrame() {
        settingsStore.resetFloatingFrame()
        if settingsStore.settings.displayMode == .floating {
            showFloating()
        }
    }

    func windowDidMove(_ notification: Notification) {
        persistFloatingFrameIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        persistFloatingFrameIfNeeded()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 286, height: 304),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .statusBar

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 286, height: 304))
        let hostingView = NSHostingView(rootView: makeRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func configurePanel(for mode: DisplayMode) {
        guard let panel else { return }
        switch mode {
        case .topPopup, .topPersistent:
            panel.styleMask.remove(.resizable)
            panel.level = .statusBar
            panel.isMovableByWindowBackground = false
        case .floating:
            panel.styleMask.insert(.resizable)
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: 250, height: 190)
        }
        panel.setContentSize(NSSize(width: 286, height: currentAlert == nil ? 304 : 360))
    }

    private func refreshContent() {
        hostingView?.rootView = makeRootView()
        if let panel, panel.isVisible {
            configurePanel(for: settingsStore.settings.displayMode)
        }
    }

    private func makeRootView() -> AnyView {
        let view = OverlayView(
            snapshot: snapshot,
            alert: currentAlert,
            onOpenMainWindow: onOpenMainWindow
        )
        return AnyView(view.preferredColorScheme(colorScheme))
    }

    private var colorScheme: ColorScheme? {
        switch settingsStore.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func topFrame(on screen: NSScreen) -> NSRect {
        let width: CGFloat = 286
        let height: CGFloat = currentAlert == nil ? 304 : 360
        let menuBarBottom = screen.visibleFrame.maxY
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: menuBarBottom - height,
            width: width,
            height: height
        )
    }

    private func screenForCurrentPointer() -> NSScreen {
        TopTriggerMonitor.screen(containing: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.settingsStore.settings.displayMode == .topPopup else { return }
                let point = NSEvent.mouseLocation
                if let screen = TopTriggerMonitor.screen(containing: point),
                   TopTriggerMonitor.triggerRect(for: screen).contains(point) || self.panel?.frame.contains(point) == true {
                    return
                }
                self.panel?.orderOut(nil)
                self.onVisibilityChanged?(false)
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func resolvedFloatingFrame() -> NSRect {
        let stored = settingsStore.settings.floatingFrame
        let size = NSSize(width: max(250, stored.width), height: max(190, stored.height))
        if stored.x == 0, stored.y == 0 {
            let visibleFrame = screenForCurrentPointer().visibleFrame
            return NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
        return NSRect(x: stored.x, y: stored.y, width: size.width, height: size.height)
    }

    private func persistFloatingFrameIfNeeded() {
        guard settingsStore.settings.displayMode == .floating, let frame = panel?.frame else { return }
        let next = CodableRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
        guard settingsStore.settings.floatingFrame != next else { return }
        settingsStore.settings.floatingFrame = next
        settingsStore.save()
    }
}
