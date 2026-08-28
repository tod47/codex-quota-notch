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

    func testPlannerEmitsInitialStatusAndSuppressesUnchangedStatusAfterDelivery() {
        let settings = addressedSettings()
        let snapshot = makeSnapshot(weeklyRemaining: 73, fiveHourRemaining: 62)
        let planner = OpenClawPushPlanner()

        let initial = planner.evaluate(
            previous: nil,
            current: snapshot,
            alerts: [],
            settings: settings,
            state: .empty
        )

        XCTAssertEqual(initial.events.count, 1)
        guard case .status(let fingerprint) = initial.events[0].kind else {
            return XCTFail("Expected an initial status event")
        }
        XCTAssertEqual(fingerprint, initial.events[0].key.replacingOccurrences(of: "status:", with: ""))

        let deliveredState = planner.markDelivered(initial.events[0], state: initial.state)
        let repeatEvaluation = planner.evaluate(
            previous: snapshot,
            current: snapshot,
            alerts: [],
            settings: settings,
            state: deliveredState
        )

        XCTAssertTrue(repeatEvaluation.events.isEmpty)
    }

    func testPlannerEmitsFiveHourResetOnceAndSuppressesStatusWhileResetIsPending() {
        let settings = addressedSettings()
        let oldSnapshot = makeSnapshot(
            weeklyRemaining: 73,
            fiveHourRemaining: 62,
            fiveHourReset: Date(timeIntervalSince1970: 1_787_306_400)
        )
        let newSnapshot = makeSnapshot(
            weeklyRemaining: 72,
            fiveHourRemaining: 100,
            fiveHourReset: Date(timeIntervalSince1970: 1_787_486_400)
        )
        let planner = OpenClawPushPlanner()

        let initial = planner.evaluate(
            previous: nil,
            current: oldSnapshot,
            alerts: [],
            settings: settings,
            state: .empty
        )
        let stateAfterInitialStatus = planner.markDelivered(initial.events[0], state: initial.state)

        let resetEvaluation = planner.evaluate(
            previous: oldSnapshot,
            current: newSnapshot,
            alerts: [],
            settings: settings,
            state: stateAfterInitialStatus
        )

        XCTAssertEqual(resetEvaluation.events.count, 1)
        guard case .fiveHourReset(let cycleID, _) = resetEvaluation.events[0].kind else {
            return XCTFail("Expected a five-hour reset event")
        }
        XCTAssertEqual(resetEvaluation.events[0].key, "five-hour-reset:\(cycleID)")
        XCTAssertNil(resetEvaluation.events.first(where: { $0.key.hasPrefix("status:") }))

        let deliveredResetState = planner.markDelivered(resetEvaluation.events[0], state: resetEvaluation.state)
        let repeatEvaluation = planner.evaluate(
            previous: newSnapshot,
            current: newSnapshot,
            alerts: [],
            settings: settings,
            state: deliveredResetState
        )

        XCTAssertTrue(repeatEvaluation.events.isEmpty)
    }

    func testPlannerPassesWeeklyAlertsAndDoesNothingWhenDisabled() {
        let snapshot = makeSnapshot(weeklyRemaining: 80, fiveHourRemaining: 60)
        let alert = QuotaAlert(
            kind: .countdown(hours: 48),
            titleKey: "alert.countdown.title",
            messageKey: "alert.countdown.twoDays"
        )
        let planner = OpenClawPushPlanner()

        let enabled = planner.evaluate(
            previous: snapshot,
            current: snapshot,
            alerts: [alert],
            settings: addressedSettings(),
            state: .empty
        )
        XCTAssertEqual(enabled.events.count, 2)
        XCTAssertTrue(enabled.events.contains { event in
            if case .alert(let value) = event.kind {
                return value == alert
            }
            return false
        })

        let disabled = planner.evaluate(
            previous: nil,
            current: snapshot,
            alerts: [alert],
            settings: OpenClawPushSettings.defaults,
            state: .empty
        )
        XCTAssertTrue(disabled.events.isEmpty)
    }

    @MainActor
    func testFormatterIncludesBothQuotasResetValuesAndDailyTokensInChinese() {
        L10n.setLanguage(.chineseSimplified)
        let snapshot = makeSnapshot(weeklyRemaining: 73, fiveHourRemaining: 62)
        let event = OpenClawPushEvent(key: "status:test", kind: .status(fingerprint: "test"))

        let message = OpenClawMessageFormatter.message(for: event, snapshot: snapshot)

        XCTAssertTrue(message.contains("周额度：73%"))
        XCTAssertTrue(message.contains("5 小时额度：62%"))
        XCTAssertTrue(message.contains("今日 token：24,000"))
        XCTAssertTrue(message.contains("重置时间"))
        XCTAssertTrue(message.contains("距离重置"))
    }

    @MainActor
    func testFormatterUsesEnglishLabelsWhenEnglishIsSelected() {
        L10n.setLanguage(.english)
        let snapshot = makeSnapshot(weeklyRemaining: 73, fiveHourRemaining: 62)
        let event = OpenClawPushEvent(key: "status:test", kind: .status(fingerprint: "test"))

        let message = OpenClawMessageFormatter.message(for: event, snapshot: snapshot)

        XCTAssertTrue(message.contains("Weekly quota: 73%"))
        XCTAssertTrue(message.contains("5-hour quota: 62%"))
        XCTAssertTrue(message.contains("Today’s tokens: 24,000"))
    }

    func testHookClientBuildsAuthenticatedDirectDeliveryRequest() async throws {
        let transport = RecordingOpenClawTransport(
            responses: [OpenClawHTTPResponse(statusCode: 200, data: Data())]
        )
        let client = OpenClawHookClient(
            transport: transport,
            retryPolicy: OpenClawRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 0)
        )
        let configuration = addressedSettings()

        try await client.send(
            message: "quota update",
            configuration: configuration,
            token: "secret-hook-token"
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:18789/hooks/agent")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-hook-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(request.url?.absoluteString.contains("secret-hook-token") == true)

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(OpenClawHookPayload.self, from: body)
        XCTAssertEqual(payload.name, "codex-quota-notch")
        XCTAssertEqual(payload.message, "quota update")
        XCTAssertTrue(payload.deliver)
        XCTAssertEqual(payload.channel, "openclaw-weixin")
        XCTAssertEqual(payload.to, "wechat-peer")
        XCTAssertEqual(payload.accountID, "default")
    }

    func testHookClientRejectsIncompleteConfigurationWithoutTransport() async {
        let transport = RecordingOpenClawTransport(
            responses: [OpenClawHTTPResponse(statusCode: 200, data: Data())]
        )
        let client = OpenClawHookClient(transport: transport)
        var configuration = addressedSettings()
        configuration.target = ""

        do {
            try await client.send(message: "quota update", configuration: configuration, token: "token")
            XCTFail("Expected incomplete configuration to fail")
        } catch let error as OpenClawHookClientError {
            XCTAssertEqual(error, .missingTarget)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testHookClientRetriesNonSuccessResponses() async throws {
        let transport = RecordingOpenClawTransport(
            responses: [
                OpenClawHTTPResponse(statusCode: 503, data: Data()),
                OpenClawHTTPResponse(statusCode: 502, data: Data()),
                OpenClawHTTPResponse(statusCode: 200, data: Data())
            ]
        )
        let client = OpenClawHookClient(
            transport: transport,
            retryPolicy: OpenClawRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 0)
        )

        try await client.send(message: "quota update", configuration: addressedSettings(), token: "token")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    private func addressedSettings() -> OpenClawPushSettings {
        OpenClawPushSettings(
            enabled: true,
            gatewayURL: "http://127.0.0.1:18789",
            channel: "openclaw-weixin",
            target: "wechat-peer",
            accountID: "default"
        )
    }

    private func makeSnapshot(
        weeklyRemaining: Int,
        fiveHourRemaining: Int,
        weeklyReset: Date = Date(timeIntervalSince1970: 1_787_306_400),
        fiveHourReset: Date = Date(timeIntervalSince1970: 1_787_320_800)
    ) -> QuotaSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_787_306_400))
        return QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(
                windowMinutes: 10_080,
                usedPercent: Double(100 - weeklyRemaining),
                resetsAt: weeklyReset,
                name: "weekly"
            ),
            secondaryLimit: RateLimitSnapshot(
                windowMinutes: 300,
                usedPercent: Double(100 - fiveHourRemaining),
                resetsAt: fiveHourReset,
                name: "five-hour"
            ),
            dailyTokens: 24_000,
            dailyTotals: [today: 24_000],
            lastUpdatedAt: Date(timeIntervalSince1970: 1_787_306_400),
            sourceStatus: .ready
        )
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

private actor RecordingOpenClawTransport: OpenClawTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [OpenClawHTTPResponse]

    init(responses: [OpenClawHTTPResponse]) {
        self.responses = responses
    }

    func perform(_ request: URLRequest) async throws -> OpenClawHTTPResponse {
        requests.append(request)
        if responses.isEmpty {
            return OpenClawHTTPResponse(statusCode: 200, data: Data())
        }
        return responses.removeFirst()
    }
}
