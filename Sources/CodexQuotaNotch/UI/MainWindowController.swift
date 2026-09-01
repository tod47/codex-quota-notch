import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let onRescan: () -> Void
    private let onChooseDataDirectory: () -> Void
    private let onTestOpenClaw: () -> Void
    private var window: NSWindow?
    private var hostingView: NSHostingView<MainWindowView>?

    init(
        settingsStore: SettingsStore,
        onRescan: @escaping () -> Void,
        onChooseDataDirectory: @escaping () -> Void,
        onTestOpenClaw: @escaping () -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.onRescan = onRescan
        self.onChooseDataDirectory = onChooseDataDirectory
        self.onTestOpenClaw = onTestOpenClaw
        super.init()
    }

    func show(snapshot: QuotaSnapshot) {
        let window = makeWindowIfNeeded(snapshot: snapshot)
        hostingView?.rootView = makeRootView(snapshot: snapshot)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(snapshot: QuotaSnapshot) {
        hostingView?.rootView = makeRootView(snapshot: snapshot)
    }

    func updateLanguage() {
        window?.title = L10n.text("app.title")
    }

    private func makeWindowIfNeeded(snapshot: QuotaSnapshot) -> NSWindow {
        if let window { return window }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("app.title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: makeRootView(snapshot: snapshot))

        self.window = window
        self.hostingView = window.contentView as? NSHostingView<MainWindowView>
        return window
    }

    private func makeRootView(snapshot: QuotaSnapshot) -> MainWindowView {
        MainWindowView(
            snapshot: snapshot,
            settingsStore: settingsStore,
            onRescan: onRescan,
            onChooseDataDirectory: onChooseDataDirectory,
            onTestOpenClaw: onTestOpenClaw
        )
    }
}
