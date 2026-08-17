import Foundation
import UserNotifications

@MainActor
public final class NotificationClient: NSObject {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func send(_ alert: QuotaAlert) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text(alert.titleKey)
        content.body = L10n.alertMessage(alert)
        content.sound = .default
        content.threadIdentifier = CodexQuotaNotchApp.buildIdentifier

        let request = UNNotificationRequest(
            identifier: "(CodexQuotaNotchApp.buildIdentifier).(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
