import AppKit
import Combine
import Foundation
import ServiceManagement

enum CodexQuotaNotchApp {
    static let buildIdentifier = "codex-quota-notch"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let triggerMonitor = TopTriggerMonitor()

    private var notificationClient: NotificationClient!
    private var model: AppModel!
    private var menuBarController: MenuBarController!
    private var overlayPanelController: OverlayPanelController!
    private var mainWindowController: MainWindowController!
    private var cancellables = Set<AnyCancellable>()
    private var lastLaunchAtLoginValue: Bool?
    private var isReady = false
    private var shouldOpenMainWindowWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        notificationClient = NotificationClient()
        notificationClient.requestAuthorization()

        model = AppModel(
            settingsStore: settingsStore,
            overlaySink: { [weak self] alert in
                self?.overlayPanelController?.present(alert: alert)
            },
            notificationSink: { [weak self] alert in
                self?.notificationClient?.send(alert)
            }
        )
        model.applySettings(settingsStore.settings)

        overlayPanelController = OverlayPanelController(settingsStore: settingsStore, snapshot: model.snapshot)
        overlayPanelController.onOpenMainWindow = { [weak self] in
            self?.openMainWindow()
        }
        overlayPanelController.onVisibilityChanged = { [weak self] isVisible in
            self?.model?.setFastRefresh(isVisible)
        }

        mainWindowController = MainWindowController(
            settingsStore: settingsStore,
            onRescan: { [weak self] in self?.model.rescan() },
            onChooseDataDirectory: { [weak self] in self?.chooseDataDirectory() }
        )

        menuBarController = MenuBarController(
            openMainWindow: { [weak self] in self?.openMainWindow() },
            refresh: { [weak self] in self?.model.rescan() },
            quit: { NSApp.terminate(nil) }
        )

        bindModel()
        overlayPanelController.updateSettings(settingsStore.settings)
        syncLaunchAtLogin(settingsStore.settings.launchAtLogin)

        triggerMonitor.onLocationChanged = { [weak self] point in
            self?.overlayPanelController?.handlePointer(point)
        }
        triggerMonitor.start()

        isReady = true
        if shouldOpenMainWindowWhenReady {
            shouldOpenMainWindowWhenReady = false
            openMainWindow()
        } else {
            // A menu bar app has no document to open when launched from Finder.
            // Present its settings window once so double-clicking the .app has
            // the same result as opening a normal macOS application.
            DispatchQueue.main.async { [weak self] in
                self?.openMainWindow()
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        requestOpenMainWindow()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestOpenMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        triggerMonitor.stop()
        model.stopSimulation()
        model.stopMonitoring()
    }

    private func bindModel() {
        model.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.menuBarController?.update(snapshot: snapshot)
                self.overlayPanelController?.update(snapshot: snapshot)
                self.mainWindowController?.update(snapshot: snapshot)
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                self.overlayPanelController?.updateSettings(settings)
                self.model?.applySettings(settings)
                self.syncLaunchAtLogin(settings.launchAtLogin)
            }
            .store(in: &cancellables)
    }

    private func openMainWindow() {
        mainWindowController.show(snapshot: model.snapshot)
    }

    private func requestOpenMainWindow() {
        guard isReady else {
            shouldOpenMainWindowWhenReady = true
            return
        }
        openMainWindow()
    }

    private func chooseDataDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("choose.folder")
        panel.message = L10n.text("data.path")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.settingsStore.settings.dataDirectoryPath = url.path
                self.settingsStore.settings.dataDirectoryBookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                self.settingsStore.save()
                self.model.updateDataDirectory(url)
            }
        }
    }

    private func syncLaunchAtLogin(_ enabled: Bool) {
        guard lastLaunchAtLoginValue != enabled else { return }
        lastLaunchAtLoginValue = enabled

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration is unavailable when running directly from SwiftPM; the
            // preference remains saved and is applied once the app is bundled.
        }
    }
}

@main
enum CodexQuotaNotchBootstrap {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
