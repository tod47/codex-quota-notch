import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private var snapshot: QuotaSnapshot
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var currentAlert: QuotaAlert?
    private var topTriggerDwellWorkItem: DispatchWorkItem?
    private var topTriggerDwellState = TopTriggerDwellState()
    private var topTriggerDwellToken = UUID()
    private var alertDismissWorkItem: DispatchWorkItem?
    private var visibilityAnimationToken = UUID()
    private var isHiding = false
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
        cancelTopTriggerDwell()
        refreshContent()

        switch settings.displayMode {
        case .topPopup:
            activeMode = .topPopup
            if panel?.isVisible == true, previousMode != .topPopup {
                hidePopup(animated: false)
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
                    self.handlePointer(NSEvent.mouseLocation)
                }
            }
        }
        alertDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func handlePointer(_ point: NSPoint) {
        guard settingsStore.settings.displayMode == .topPopup else {
            cancelTopTriggerDwell()
            return
        }
        guard let screen = TopTriggerMonitor.screen(containing: point) else {
            cancelTopTriggerDwell()
            if panel?.isVisible == true {
                hidePopup()
            }
            return
        }

        let inTrigger = TopTriggerMonitor.triggerRect(for: screen).contains(point)
        let inPanel = panel?.isVisible == true && panel?.frame.contains(point) == true
        if inTrigger {
            if panel?.isVisible == true {
                cancelTopTriggerDwell()
                keepTopPopupVisible(on: screen)
            } else {
                beginTopTriggerDwell()
            }
        } else if inPanel {
            cancelTopTriggerDwell()
            keepTopPopupVisible(on: screen)
        } else {
            cancelTopTriggerDwell()
            if panel?.isVisible == true {
                hidePopup()
            }
        }
    }

    func showTopPopup(on screen: NSScreen) {
        cancelTopTriggerDwell()
        let panel = makePanelIfNeeded()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.01
        let shouldAnimate = !wasVisible || activeMode != .topPopup
        invalidateVisibilityAnimation()
        isHiding = false
        configurePanel(for: .topPopup)
        let frame = topFrame(on: screen)
        activeMode = .topPopup

        if shouldAnimate {
            panel.alphaValue = 0
            panel.setFrame(collapsedTopFrame(for: frame), display: false)
            panel.orderFrontRegardless()
            onVisibilityChanged?(true)
            animateTopPopupIn(panel: panel, to: frame)
        } else {
            panel.alphaValue = 1
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }

    func showPersistent() {
        cancelTopTriggerDwell()
        invalidateVisibilityAnimation()
        isHiding = false
        let panel = makePanelIfNeeded()
        configurePanel(for: .topPersistent)
        panel.alphaValue = 1
        panel.setFrame(topFrame(on: screenForCurrentPointer()), display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
        activeMode = .topPersistent
    }

    func showFloating() {
        cancelTopTriggerDwell()
        invalidateVisibilityAnimation()
        isHiding = false
        let panel = makePanelIfNeeded()
        configurePanel(for: .floating)
        panel.alphaValue = 1
        let frame = resolvedFloatingFrame()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
        activeMode = .floating
    }

    func hidePopup() {
        hidePopup(animated: true)
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
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .statusBar

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 286, height: 304))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.isOpaque = false
        let hostingView = NSHostingView(rootView: makeRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
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

    private func beginTopTriggerDwell() {
        guard topTriggerDwellState.isActive == false, topTriggerDwellWorkItem == nil else { return }

        topTriggerDwellState.enter(at: Date())
        let token = UUID()
        topTriggerDwellToken = token
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.topTriggerDwellToken == token else { return }
                self.topTriggerDwellWorkItem = nil

                let point = NSEvent.mouseLocation
                guard let screen = TopTriggerMonitor.screen(containing: point),
                      TopTriggerMonitor.triggerRect(for: screen).contains(point),
                      self.topTriggerDwellState.activateIfReady(at: Date()) else {
                    self.cancelTopTriggerDwell()
                    return
                }

                self.showTopPopup(on: screen)
            }
        }
        topTriggerDwellWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TopTriggerDwellState.defaultDwellTime,
            execute: workItem
        )
    }

    private func cancelTopTriggerDwell() {
        topTriggerDwellWorkItem?.cancel()
        topTriggerDwellWorkItem = nil
        topTriggerDwellToken = UUID()
        topTriggerDwellState.leave()
    }

    private func keepTopPopupVisible(on screen: NSScreen) {
        guard let panel else { return }
        invalidateVisibilityAnimation()
        isHiding = false
        panel.alphaValue = 1
        panel.setFrame(topFrame(on: screen), display: true)
        panel.orderFrontRegardless()
    }

    private func animateTopPopupIn(panel: NSPanel, to frame: NSRect) {
        let animationToken = visibilityAnimationToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, self.visibilityAnimationToken == animationToken else { return }
                panel?.alphaValue = 1
            }
        }
    }

    private func hidePopup(animated: Bool) {
        cancelTopTriggerDwell()
        guard let panel, panel.isVisible else { return }

        if animated, isHiding { return }

        invalidateVisibilityAnimation()
        let animationToken = visibilityAnimationToken
        let collapsedFrame = collapsedTopFrame(for: panel.frame)

        guard animated else {
            isHiding = false
            panel.orderOut(nil)
            panel.alphaValue = 1
            onVisibilityChanged?(false)
            return
        }

        isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapsedFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, self.visibilityAnimationToken == animationToken, let panel else { return }
                self.isHiding = false
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.onVisibilityChanged?(false)
            }
        }
    }

    private func invalidateVisibilityAnimation() {
        visibilityAnimationToken = UUID()
    }

    private func collapsedTopFrame(for frame: NSRect) -> NSRect {
        let collapsedHeight: CGFloat = 10
        return NSRect(
            x: frame.minX,
            y: frame.maxY - collapsedHeight,
            width: frame.width,
            height: collapsedHeight
        )
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
