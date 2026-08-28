import Foundation
import XCTest
@testable import CodexQuotaNotch

@MainActor
final class OpenClawIntegrationTests: XCTestCase {
    func testOpenClawDefaultsAreSafeAndDisabled() {
        let settings = OpenClawPushSettings.defaults

        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.gatewayURL, "http://127.0.0.1:18789")
        XCTAssertEqual(settings.channel, "openclaw-weixin")
        XCTAssertTrue(settings.statusUpdatesEnabled)
        XCTAssertTrue(settings.alertsEnabled)
        XCTAssertFalse(settings.isAddressed)
    }

    func testLegacyAppSettingsWithoutOpenClawUseSafeDefaults() throws {
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "openClaw")

        let reloaded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        XCTAssertEqual(reloaded.openClaw, .defaults)
    }

    func testOpenClawStateRoundTripsThroughSettingsStore() {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.openclaw-state")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.openclaw-state")
        let secrets = InMemorySecretStore()
        let store = SettingsStore(defaults: defaults, secretStore: secrets)

        store.openClawPushState = OpenClawPushState(
            lastDeliveredStatusFingerprint: "weekly:73|five:62",
            observedFiveHourCycleID: "1787306400",
            pendingFiveHourCycleID: "1787486400",
            lastDeliveredFiveHourCycleID: "1787306400"
        )
        store.save()

        let reloaded = SettingsStore(defaults: defaults, secretStore: secrets)

        XCTAssertEqual(
            reloaded.openClawPushState,
            OpenClawPushState(
                lastDeliveredStatusFingerprint: "weekly:73|five:62",
                observedFiveHourCycleID: "1787306400",
                pendingFiveHourCycleID: "1787486400",
                lastDeliveredFiveHourCycleID: "1787306400"
            )
        )
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.openclaw-state")
    }

    func testTokenIsStoredOutsideAppSettingsAndUserDefaults() throws {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.openclaw-token")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.openclaw-token")
        let secrets = InMemorySecretStore()
        let store = SettingsStore(defaults: defaults, secretStore: secrets)

        XCTAssertTrue(store.saveOpenClawToken("secret-hook-token"))
        store.save()

        XCTAssertEqual(store.openClawToken, "secret-hook-token")
        XCTAssertEqual(try secrets.read(key: "openclaw-hook-token"), "secret-hook-token")

        let encodedSettings = try JSONEncoder().encode(store.settings)
        let encodedText = String(decoding: encodedSettings, as: UTF8.self)
        XCTAssertFalse(encodedText.contains("secret-hook-token"))
        XCTAssertFalse(
            defaults.dictionaryRepresentation().values.contains { value in
                String(describing: value).contains("secret-hook-token")
            }
        )

        XCTAssertTrue(store.clearOpenClawToken())
        XCTAssertNil(store.openClawToken)
        XCTAssertNil(try secrets.read(key: "openclaw-hook-token"))
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.openclaw-token")
    }

    func testInMemorySecretStoreSupportsReadWriteAndDelete() throws {
        let secrets = InMemorySecretStore()

        XCTAssertNil(try secrets.read(key: "token"))
        try secrets.write("value", key: "token")
        XCTAssertEqual(try secrets.read(key: "token"), "value")
        try secrets.delete(key: "token")
        XCTAssertNil(try secrets.read(key: "token"))
    }
}

private final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]

    func read(key: String) throws -> String? {
        values[key]
    }

    func write(_ value: String, key: String) throws {
        values[key] = value
    }

    func delete(key: String) throws {
        values.removeValue(forKey: key)
    }
}
