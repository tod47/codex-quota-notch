import Foundation
import XCTest
@testable import CodexQuotaNotch

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testFloatingModeDoesNotForcePopupContentSize() {
        XCTAssertNil(OverlayPanelSizing.fixedContentSize(for: .floating, hasAlert: false))
        XCTAssertEqual(
            OverlayPanelSizing.fixedContentSize(for: .topPopup, hasAlert: false),
            NSSize(width: 286, height: 304)
        )
        XCTAssertEqual(
            OverlayPanelSizing.fixedContentSize(for: .topPersistent, hasAlert: true),
            NSSize(width: 286, height: 360)
        )
        XCTAssertEqual(
            OverlayPanelSizing.fixedContentSize(
                for: .topPopup,
                hasAlert: false,
                hasFiveHourLimit: true
            ),
            NSSize(width: 286, height: 410)
        )
        XCTAssertEqual(
            OverlayPanelSizing.fixedContentSize(
                for: .topPersistent,
                hasAlert: true,
                hasFiveHourLimit: true
            ),
            NSSize(width: 286, height: 470)
        )
        XCTAssertEqual(
            OverlayPanelSizing.floatingMinimumHeight(hasAlert: false, hasFiveHourLimit: false),
            190
        )
        XCTAssertEqual(
            OverlayPanelSizing.floatingMinimumHeight(hasAlert: false, hasFiveHourLimit: true),
            410
        )
        XCTAssertEqual(
            OverlayPanelSizing.floatingMinimumHeight(hasAlert: true, hasFiveHourLimit: true),
            470
        )
    }

    func testDefaultsMatchApprovedProductBehavior() {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.displayMode, .topPopup)
        XCTAssertTrue(settings.showFiveHourQuota)
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
        store.settings.showFiveHourQuota = false
        store.settings.language = .chineseSimplified
        store.settings.floatingFrame = CodableRect(x: 40, y: 70, width: 310, height: 220)
        store.settings.ordinaryStep = 5
        store.save()

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.appearance, .dark)
        XCTAssertEqual(reloaded.settings.displayMode, .floating)
        XCTAssertFalse(reloaded.settings.showFiveHourQuota)
        XCTAssertEqual(reloaded.settings.language, .chineseSimplified)
        XCTAssertEqual(reloaded.settings.floatingFrame.width, 310)
        XCTAssertEqual(reloaded.settings.ordinaryStep, 5)

        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.settings")
    }

    func testLegacySettingsWithoutLanguageDefaultToSystem() throws {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.legacy-settings")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.legacy-settings")

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "language")
        legacyObject.removeValue(forKey: "showFiveHourQuota")
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacyObject),
            forKey: "codex-quota-notch.settings.v1"
        )

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings.language, .system)
        XCTAssertEqual(reloaded.settings.displayMode, .topPopup)
        XCTAssertTrue(reloaded.settings.showFiveHourQuota)
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.legacy-settings")
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
