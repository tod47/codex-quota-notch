import Foundation

public struct OpenClawPushSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var gatewayURL: String
    public var channel: String
    public var target: String
    public var accountID: String
    public var statusUpdatesEnabled: Bool
    public var alertsEnabled: Bool

    public init(
        enabled: Bool = false,
        gatewayURL: String = "http://127.0.0.1:18789",
        channel: String = "openclaw-weixin",
        target: String = "",
        accountID: String = "",
        statusUpdatesEnabled: Bool = true,
        alertsEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.gatewayURL = gatewayURL
        self.channel = channel
        self.target = target
        self.accountID = accountID
        self.statusUpdatesEnabled = statusUpdatesEnabled
        self.alertsEnabled = alertsEnabled
    }

    public static let defaults = OpenClawPushSettings()

    public var isAddressed: Bool {
        enabled
            && !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Excludes the secret token so changing a token does not leak into settings data.
    public var deliveryFingerprint: String {
        [
            String(enabled),
            gatewayURL,
            channel,
            target,
            accountID,
            String(statusUpdatesEnabled),
            String(alertsEnabled)
        ].joined(separator: "|")
    }
}

public struct OpenClawPushState: Codable, Equatable, Sendable {
    public var lastDeliveredStatusFingerprint: String?
    public var observedFiveHourCycleID: String?
    public var pendingFiveHourCycleID: String?
    public var lastDeliveredFiveHourCycleID: String?

    public init(
        lastDeliveredStatusFingerprint: String? = nil,
        observedFiveHourCycleID: String? = nil,
        pendingFiveHourCycleID: String? = nil,
        lastDeliveredFiveHourCycleID: String? = nil
    ) {
        self.lastDeliveredStatusFingerprint = lastDeliveredStatusFingerprint
        self.observedFiveHourCycleID = observedFiveHourCycleID
        self.pendingFiveHourCycleID = pendingFiveHourCycleID
        self.lastDeliveredFiveHourCycleID = lastDeliveredFiveHourCycleID
    }

    public static let empty = OpenClawPushState()
}

public enum OpenClawDeliveryStatus: Equatable, Sendable {
    case idle
    case notConfigured
    case sending
    case delivered
    case failed
}
