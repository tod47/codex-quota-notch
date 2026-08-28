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

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case english
    case chineseSimplified

    var resourceIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .chineseSimplified: return "zh-hans"
        }
    }
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
    public var language: AppLanguage
    public var appearance: AppearanceMode
    public var displayMode: DisplayMode
    public var showFiveHourQuota: Bool
    public var openClaw: OpenClawPushSettings
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
    public var simulationMode: Bool

    public static var defaults: AppSettings {
        AppSettings(
            language: .system,
            appearance: .system,
            displayMode: .topPopup,
            openClaw: .defaults,
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
            floatingFrame: CodableRect(x: 0, y: 0, width: 320, height: 230),
            simulationMode: false,
            showFiveHourQuota: true
        )
    }

    public init(
        language: AppLanguage = .system,
        appearance: AppearanceMode,
        displayMode: DisplayMode,
        openClaw: OpenClawPushSettings = .defaults,
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
        floatingFrame: CodableRect,
        simulationMode: Bool,
        showFiveHourQuota: Bool = true
    ) {
        self.language = language
        self.appearance = appearance
        self.displayMode = displayMode
        self.showFiveHourQuota = showFiveHourQuota
        self.openClaw = openClaw
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
        self.simulationMode = simulationMode
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case appearance
        case displayMode
        case showFiveHourQuota
        case openClaw
        case launchAtLogin
        case overlayAlertsEnabled
        case systemNotificationsEnabled
        case percentageAlertsEnabled
        case criticalAlertsEnabled
        case countdownAlertsEnabled
        case resetAlertsEnabled
        case exhaustedAlertsEnabled
        case ordinaryStep
        case criticalStart
        case criticalStep
        case countdownHours
        case dataDirectoryBookmark
        case dataDirectoryPath
        case floatingFrame
        case simulationMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            language: try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system,
            appearance: try container.decode(AppearanceMode.self, forKey: .appearance),
            displayMode: try container.decode(DisplayMode.self, forKey: .displayMode),
            openClaw: try container.decodeIfPresent(OpenClawPushSettings.self, forKey: .openClaw) ?? .defaults,
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin),
            overlayAlertsEnabled: try container.decode(Bool.self, forKey: .overlayAlertsEnabled),
            systemNotificationsEnabled: try container.decode(Bool.self, forKey: .systemNotificationsEnabled),
            percentageAlertsEnabled: try container.decode(Bool.self, forKey: .percentageAlertsEnabled),
            criticalAlertsEnabled: try container.decode(Bool.self, forKey: .criticalAlertsEnabled),
            countdownAlertsEnabled: try container.decode(Bool.self, forKey: .countdownAlertsEnabled),
            resetAlertsEnabled: try container.decode(Bool.self, forKey: .resetAlertsEnabled),
            exhaustedAlertsEnabled: try container.decode(Bool.self, forKey: .exhaustedAlertsEnabled),
            ordinaryStep: try container.decode(Int.self, forKey: .ordinaryStep),
            criticalStart: try container.decode(Int.self, forKey: .criticalStart),
            criticalStep: try container.decode(Int.self, forKey: .criticalStep),
            countdownHours: try container.decode([Int].self, forKey: .countdownHours),
            dataDirectoryBookmark: try container.decodeIfPresent(Data.self, forKey: .dataDirectoryBookmark),
            dataDirectoryPath: try container.decode(String.self, forKey: .dataDirectoryPath),
            floatingFrame: try container.decode(CodableRect.self, forKey: .floatingFrame),
            simulationMode: try container.decode(Bool.self, forKey: .simulationMode),
            showFiveHourQuota: try container.decodeIfPresent(Bool.self, forKey: .showFiveHourQuota) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(showFiveHourQuota, forKey: .showFiveHourQuota)
        try container.encode(openClaw, forKey: .openClaw)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(overlayAlertsEnabled, forKey: .overlayAlertsEnabled)
        try container.encode(systemNotificationsEnabled, forKey: .systemNotificationsEnabled)
        try container.encode(percentageAlertsEnabled, forKey: .percentageAlertsEnabled)
        try container.encode(criticalAlertsEnabled, forKey: .criticalAlertsEnabled)
        try container.encode(countdownAlertsEnabled, forKey: .countdownAlertsEnabled)
        try container.encode(resetAlertsEnabled, forKey: .resetAlertsEnabled)
        try container.encode(exhaustedAlertsEnabled, forKey: .exhaustedAlertsEnabled)
        try container.encode(ordinaryStep, forKey: .ordinaryStep)
        try container.encode(criticalStart, forKey: .criticalStart)
        try container.encode(criticalStep, forKey: .criticalStep)
        try container.encode(countdownHours, forKey: .countdownHours)
        try container.encode(dataDirectoryBookmark, forKey: .dataDirectoryBookmark)
        try container.encode(dataDirectoryPath, forKey: .dataDirectoryPath)
        try container.encode(floatingFrame, forKey: .floatingFrame)
        try container.encode(simulationMode, forKey: .simulationMode)
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
    @Published public var openClawPushState: OpenClawPushState
    @Published public private(set) var openClawDeliveryStatus: OpenClawDeliveryStatus = .idle

    private let defaults: UserDefaults
    private let secretStore: any SecretStore
    private let settingsKey = "codex-quota-notch.settings.v1"
    private let alertStateKey = "codex-quota-notch.alert-state.v1"
    private let openClawStateKey = "codex-quota-notch.openclaw-state.v1"
    private let openClawTokenKey = "openclaw-hook-token"

    @Published public private(set) var openClawToken: String?

    public init(
        defaults: UserDefaults = .standard,
        secretStore: any SecretStore = KeychainSecretStore()
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
        self.openClawToken = try? secretStore.read(key: openClawTokenKey)

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

        if let data = defaults.data(forKey: openClawStateKey),
           let decoded = try? JSONDecoder().decode(OpenClawPushState.self, from: data) {
            openClawPushState = decoded
        } else {
            openClawPushState = .empty
        }
    }

    public func save() {
        let encoder = JSONEncoder()
        if let settingsData = try? encoder.encode(settings.normalized()),
           let stateData = try? encoder.encode(alertState),
           let openClawStateData = try? encoder.encode(openClawPushState) {
            defaults.set(settingsData, forKey: settingsKey)
            defaults.set(stateData, forKey: alertStateKey)
            defaults.set(openClawStateData, forKey: openClawStateKey)
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

    public func updateOpenClawPushState(_ state: OpenClawPushState) {
        openClawPushState = state
        save()
    }

    public func resetOpenClawPushState() {
        openClawPushState = .empty
        openClawDeliveryStatus = .idle
        save()
    }

    @discardableResult
    public func saveOpenClawToken(_ token: String) -> Bool {
        do {
            if token.isEmpty {
                try secretStore.delete(key: openClawTokenKey)
                openClawToken = nil
            } else {
                try secretStore.write(token, key: openClawTokenKey)
                openClawToken = token
            }
            resetOpenClawPushState()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func clearOpenClawToken() -> Bool {
        saveOpenClawToken("")
    }

    public func updateOpenClawDeliveryStatus(_ status: OpenClawDeliveryStatus) {
        openClawDeliveryStatus = status
    }
}
