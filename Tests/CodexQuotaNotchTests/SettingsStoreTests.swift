import Foundation
import XCTest
@testable import CodexQuotaNotch

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchApprovedProductBehavior() {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.displayMode, .topPopup)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.overlayAlertsEnabled)
        XCTAssertTrue(settings.systemNotificationsEnabled)
        XCTAssertEqual(settings.ordinaryStep, 10)
        XCTAssertEqual(settings.criticalStart, 10)
        XCTAssertEqual(settings.criticalStep, 1)
        XCTAssertEqual(settings.countdownHours, [48, 24, 5])
    }

    func testSettingsRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.settings")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.settings")

        let store = SettingsStore(defaults: defaults)
        store.settings.appearance = .dark
        store.settings.displayMode = .floating
        store.settings.floatingFrame = CodableRect(x: 40, y: 70, width: 310, height: 220)
        store.settings.ordinaryStep = 5
        store.save()

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.appearance, .dark)
        XCTAssertEqual(reloaded.settings.displayMode, .floating)
        XCTAssertEqual(reloaded.settings.floatingFrame.width, 310)
        XCTAssertEqual(reloaded.settings.ordinaryStep, 5)

        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.settings")
    }

    func testResetFloatingFrameRestoresDefault() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.frame")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.frame")
        let store = SettingsStore(defaults: defaults)

        store.settings.floatingFrame = CodableRect(x: 1, y: 2, width: 400, height: 300)
        store.resetFloatingFrame()

        XCTAssertEqual(store.settings.floatingFrame, AppSettings.defaults.floatingFrame)
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.frame")
    }
}
