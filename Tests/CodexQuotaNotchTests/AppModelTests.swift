import Foundation
import XCTest
@testable import CodexQuotaNotch

@MainActor
final class AppModelTests: XCTestCase {
    func testAlertRoutesToBothEnabledSinks() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model")
        let settings = SettingsStore(defaults: defaults)
        var overlayAlerts: [QuotaAlert] = []
        var notificationAlerts: [QuotaAlert] = []

        let model = AppModel(
            settingsStore: settings,
            startMonitoring: false,
            overlaySink: { overlayAlerts.append($0) },
            notificationSink: { notificationAlerts.append($0) }
        )

        model.handle(snapshot: snapshot(remaining: 100))
        model.handle(snapshot: snapshot(remaining: 78))

        XCTAssertEqual(overlayAlerts.map(\.kind), [.percentage(80)])
        XCTAssertEqual(notificationAlerts.map(\.kind), [.percentage(80)])
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model")
    }

    func testDisabledNotificationSinkDoesNotReceiveAlert() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model-disabled")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-disabled")
        let settings = SettingsStore(defaults: defaults)
        settings.settings.systemNotificationsEnabled = false
        var notificationAlerts: [QuotaAlert] = []

        let model = AppModel(
            settingsStore: settings,
            startMonitoring: false,
            overlaySink: { _ in },
            notificationSink: { notificationAlerts.append($0) }
        )

        model.handle(snapshot: snapshot(remaining: 78))

        XCTAssertTrue(notificationAlerts.isEmpty)
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-disabled")
    }

    func testSimulationModeProducesSyntheticWeeklySnapshot() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model-simulation")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-simulation")
        let settings = SettingsStore(defaults: defaults)
        let model = AppModel(settingsStore: settings, startMonitoring: false)

        var simulationSettings = settings.settings
        simulationSettings.simulationMode = true
        model.applySettings(simulationSettings)

        XCTAssertEqual(model.snapshot.weeklyLimit?.windowMinutes, 10_080)
        XCTAssertEqual(model.snapshot.remainingPercent, 80)
        XCTAssertEqual(model.snapshot.fiveHourLimit?.windowMinutes, 300)
        XCTAssertEqual(model.snapshot.fiveHourRemainingPercent, 75)
        XCTAssertEqual(model.snapshot.sourceStatus, .ready)

        model.stopSimulation()
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-simulation")
    }

    private func snapshot(remaining: Int) -> QuotaSnapshot {
        let reset = Date().addingTimeInterval(7 * 24 * 60 * 60)
        return QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(windowMinutes: 10_080, usedPercent: Double(100 - remaining), resetsAt: reset),
            secondaryLimit: nil,
            dailyTokens: 100,
            lastUpdatedAt: Date(),
            sourceStatus: .ready
        )
    }
}
