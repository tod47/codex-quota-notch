import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let openMainWindowAction: () -> Void
    private let refreshAction: () -> Void
    private let quitAction: () -> Void
    private var contextMenu: NSMenu?

    init(
        openMainWindow: @escaping () -> Void,
        refresh: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        openMainWindowAction = openMainWindow
        refreshAction = refresh
        quitAction = quit
        super.init()
        configure()
    }

    func update(snapshot: QuotaSnapshot) {
        let title = snapshot.remainingPercent.map { "\($0)%" } ?? "Codex —"
        let color: NSColor
        if let remaining = snapshot.remainingPercent {
            if remaining <= 10 {
                color = .systemRed
            } else if remaining <= 30 {
                color = .systemOrange
            } else {
                color = .systemGreen
            }
        } else {
            color = .secondaryLabelColor
        }

        statusItem.button?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color
            ]
        )
        statusItem.button?.toolTip = L10n.text("app.weekly.quota")
    }

    private func configure() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateLanguage()
    }

    func updateLanguage() {
        statusItem.button?.toolTip = L10n.text("app.weekly.quota")
        contextMenu = makeContextMenu()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: L10n.text("open.main.window"), action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: L10n.text("refresh"), action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.text("quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func handleStatusItemClick() {
        switch MenuBarClickPolicy.action(for: NSApp.currentEvent?.type) {
        case .openSettings:
            openMainWindow()
        case .showMenu:
            showContextMenu()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button, let contextMenu else { return }
        contextMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    @objc private func openMainWindow() {
        openMainWindowAction()
    }

    @objc private func refresh() {
        refreshAction()
    }

    @objc private func quit() {
        quitAction()
    }
}
