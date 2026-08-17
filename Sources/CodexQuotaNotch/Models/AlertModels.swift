import Foundation

public struct AlertSettings: Codable, Equatable, Sendable {
    public var ordinaryStep: Int
    public var criticalStart: Int
    public var criticalStep: Int
    public var countdownHours: [Int]
    public var percentageAlertsEnabled: Bool
    public var criticalAlertsEnabled: Bool
    public var countdownAlertsEnabled: Bool
    public var resetAlertsEnabled: Bool
    public var exhaustedAlertsEnabled: Bool
    public var overlayAlertsEnabled: Bool
    public var systemNotificationsEnabled: Bool

    public init(
        ordinaryStep: Int = 10,
        criticalStart: Int = 10,
        criticalStep: Int = 1,
        countdownHours: [Int] = [48, 24, 5],
        percentageAlertsEnabled: Bool = true,
        criticalAlertsEnabled: Bool = true,
        countdownAlertsEnabled: Bool = true,
        resetAlertsEnabled: Bool = true,
        exhaustedAlertsEnabled: Bool = true,
        overlayAlertsEnabled: Bool = true,
        systemNotificationsEnabled: Bool = true
    ) {
        self.ordinaryStep = ordinaryStep
        self.criticalStart = criticalStart
        self.criticalStep = criticalStep
        self.countdownHours = countdownHours
        self.percentageAlertsEnabled = percentageAlertsEnabled
        self.criticalAlertsEnabled = criticalAlertsEnabled
        self.countdownAlertsEnabled = countdownAlertsEnabled
        self.resetAlertsEnabled = resetAlertsEnabled
        self.exhaustedAlertsEnabled = exhaustedAlertsEnabled
        self.overlayAlertsEnabled = overlayAlertsEnabled
        self.systemNotificationsEnabled = systemNotificationsEnabled
    }

    public static let defaults = AlertSettings()
}

public enum AlertKind: Codable, Equatable, Hashable, Sendable {
    case percentage(Int)
    case countdown(hours: Int)
    case reset
    case exhausted
}

public struct AlertState: Codable, Equatable, Sendable {
    public var cycleID: String?
    public var emittedKeys: Set<String>

    public init(cycleID: String? = nil, emittedKeys: Set<String> = []) {
        self.cycleID = cycleID
        self.emittedKeys = emittedKeys
    }

    public static let empty = AlertState()
}
