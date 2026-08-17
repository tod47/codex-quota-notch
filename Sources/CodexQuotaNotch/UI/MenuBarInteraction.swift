import AppKit

enum MenuBarClickAction: Equatable {
    case openSettings
    case showMenu
}

enum MenuBarClickPolicy {
    static func action(for eventType: NSEvent.EventType?) -> MenuBarClickAction {
        eventType == .rightMouseUp ? .showMenu : .openSettings
    }
}
