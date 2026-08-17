import Combine
import Foundation

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case topPopup
    case topPersistent
    case floating
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public struct CodableRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode
    public var displayMode: DisplayMode
    public var launchAtLogin: Bool
    public var overlayAlertsEnabled: Bool
    public var systemNotificationsEnabled: Bool
    public var percentageAlertsEnabled: Bool
    public var criticalAlertsEnabled: Bool
    public var countdownAlertsEnabled: Bool
    public var resetAlertsEnabled: Bool
    public var exhaustedAlertsEnabled: Bool
    public var ordinaryStep: Int
    public var criticalStart: Int
    public var criticalStep: Int
    public var countdownHours: [Int]
    public var dataDirectoryBookmark: Data?
    public var dataDirectoryPath: String
    public var floatingFrame: CodableRect

    public static var defaults: AppSettings {
        AppSettings(
            appearance: .system,
            displayMode: .topPopup,
            launchAtLogin: true,
            overlayAlertsEnabled: true,
            systemNotificationsEnabled: true,
            percentageAlertsEnabled: true,
            criticalAlertsEnabled: true,
            countdownAlertsEnabled: true,
            resetAlertsEnabled: true,
            exhaustedAlertsEnabled: true,
            ordinaryStep: 10,
            criticalStart: 10,
            criticalStep: 1,
            countdownHours: [48, 24, 5],
            dataDirectoryBookmark: nil,
            dataDirectoryPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true).path,
            floatingFrame: CodableRect(x: 0, y: 0, width: 320, height: 230)
        )
    }

    public init(
        appearance: AppearanceMode,
        displayMode: DisplayMode,
        launchAtLogin: Bool,
        overlayAlertsEnabled: Bool,
        systemNotificationsEnabled: Bool,
        percentageAlertsEnabled: Bool,
        criticalAlertsEnabled: Bool,
        countdownAlertsEnabled: Bool,
        resetAlertsEnabled: Bool,
        exhaustedAlertsEnabled: Bool,
        ordinaryStep: Int,
        criticalStart: Int,
        criticalStep: Int,
        countdownHours: [Int],
        dataDirectoryBookmark: Data?,
        dataDirectoryPath: String,
        floatingFrame: CodableRect
    ) {
        self.appearance = appearance
        self.displayMode = displayMode
        self.launchAtLogin = launchAtLogin
        self.overlayAlertsEnabled = overlayAlertsEnabled
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.percentageAlertsEnabled = percentageAlertsEnabled
        self.criticalAlertsEnabled = criticalAlertsEnabled
        self.countdownAlertsEnabled = countdownAlertsEnabled
        self.resetAlertsEnabled = resetAlertsEnabled
        self.exhaustedAlertsEnabled = exhaustedAlertsEnabled
        self.ordinaryStep = ordinaryStep
        self.criticalStart = criticalStart
        self.criticalStep = criticalStep
        self.countdownHours = countdownHours
        self.dataDirectoryBookmark = dataDirectoryBookmark
        self.dataDirectoryPath = dataDirectoryPath
        self.floatingFrame = floatingFrame
    }

    public var alertSettings: AlertSettings {
        AlertSettings(
            ordinaryStep: ordinaryStep,
            criticalStart: criticalStart,
            criticalStep: criticalStep,
            countdownHours: countdownHours,
            percentageAlertsEnabled: percentageAlertsEnabled,
            criticalAlertsEnabled: criticalAlertsEnabled,
            countdownAlertsEnabled: countdownAlertsEnabled,
            resetAlertsEnabled: resetAlertsEnabled,
            exhaustedAlertsEnabled: exhaustedAlertsEnabled,
            overlayAlertsEnabled: overlayAlertsEnabled,
            systemNotificationsEnabled: systemNotificationsEnabled
        )
    }

    public func normalized() -> AppSettings {
        var copy = self
        copy.ordinaryStep = min(50, max(1, ordinaryStep))
        copy.criticalStart = min(50, max(1, criticalStart))
        copy.criticalStep = min(10, max(1, criticalStep))
        copy.countdownHours = countdownHours.filter { $0 > 0 }.sorted(by: >)
        if copy.countdownHours.isEmpty {
            copy.countdownHours = AppSettings.defaults.countdownHours
        }
        return copy
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var alertState: AlertState

    private let defaults: UserDefaults
    private let settingsKey = "codex-quota-notch.settings.v1"
    private let alertStateKey = "codex-quota-notch.alert-state.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded.normalized()
        } else {
            settings = .defaults
        }

        if let data = defaults.data(forKey: alertStateKey),
           let decoded = try? JSONDecoder().decode(AlertState.self, from: data) {
            alertState = decoded
        } else {
            alertState = .empty
        }
    }

    public func save() {
        let encoder = JSONEncoder()
        if let settingsData = try? encoder.encode(settings.normalized()),
           let stateData = try? encoder.encode(alertState) {
            defaults.set(settingsData, forKey: settingsKey)
            defaults.set(stateData, forKey: alertStateKey)
        }
    }

    public func updateAlertState(_ state: AlertState) {
        alertState = state
        save()
    }

    public func resetFloatingFrame() {
        settings.floatingFrame = AppSettings.defaults.floatingFrame
        save()
    }
}
