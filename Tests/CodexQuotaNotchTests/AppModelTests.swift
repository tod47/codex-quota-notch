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

    func testConfiguredOpenClawReceivesInitialStatusOnlyOnceForUnchangedSnapshot() async throws {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model-openclaw-status")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-status")
        let secrets = InMemoryAppModelSecretStore()
        let settings = SettingsStore(defaults: defaults, secretStore: secrets)
        settings.settings.openClaw = addressedOpenClawSettings()
        XCTAssertTrue(settings.saveOpenClawToken("token"))

        let transport = AppModelRecordingTransport(
            responses: [OpenClawHTTPResponse(statusCode: 200, data: Data())]
        )
        let client = OpenClawHookClient(
            transport: transport,
            retryPolicy: OpenClawRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
        )
        let model = AppModel(
            settingsStore: settings,
            startMonitoring: false,
            openClawClient: client
        )
        let snapshot = snapshot(remaining: 73, fiveHourRemaining: 62)

        model.handle(snapshot: snapshot)
        try await waitForRequestCount(1, on: transport)
        model.handle(snapshot: snapshot)
        try await Task.sleep(nanoseconds: 20_000_000)

        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-status")
    }

    func testConfiguredOpenClawSendsFiveHourResetAfterCycleChanges() async throws {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model-openclaw-reset")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-reset")
        let secrets = InMemoryAppModelSecretStore()
        let settings = SettingsStore(defaults: defaults, secretStore: secrets)
        settings.settings.openClaw = addressedOpenClawSettings()
        XCTAssertTrue(settings.saveOpenClawToken("token"))

        let transport = AppModelRecordingTransport(
            responses: [
                OpenClawHTTPResponse(statusCode: 200, data: Data()),
                OpenClawHTTPResponse(statusCode: 200, data: Data())
            ]
        )
        let model = AppModel(
            settingsStore: settings,
            startMonitoring: false,
            openClawClient: OpenClawHookClient(
                transport: transport,
                retryPolicy: OpenClawRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            )
        )
        let first = snapshot(
            remaining: 73,
            fiveHourRemaining: 62,
            fiveHourReset: Date(timeIntervalSince1970: 1_787_320_800)
        )
        let second = snapshot(
            remaining: 72,
            fiveHourRemaining: 100,
            fiveHourReset: Date(timeIntervalSince1970: 1_787_486_400)
        )

        model.handle(snapshot: first)
        try await waitForRequestCount(1, on: transport)
        model.handle(snapshot: second)
        try await waitForRequestCount(2, on: transport)

        let messages = await transport.messageValues()
        XCTAssertTrue(messages[1].contains("5 小时额度已重置"))
        XCTAssertTrue(messages[1].contains("5 小时额度：100%"))
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-reset")
    }

    func testFailedOpenClawAlertIsRetriedOnTheNextSnapshot() async throws {
        let defaults = UserDefaults(suiteName: "CodexQuotaNotchTests.app-model-openclaw-retry")!
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-retry")
        let secrets = InMemoryAppModelSecretStore()
        let settings = SettingsStore(defaults: defaults, secretStore: secrets)
        var openClawSettings = addressedOpenClawSettings()
        openClawSettings.statusUpdatesEnabled = false
        settings.settings.openClaw = openClawSettings
        XCTAssertTrue(settings.saveOpenClawToken("token"))

        let transport = AppModelRecordingTransport(
            responses: [
                OpenClawHTTPResponse(statusCode: 503, data: Data()),
                OpenClawHTTPResponse(statusCode: 502, data: Data()),
                OpenClawHTTPResponse(statusCode: 503, data: Data()),
                OpenClawHTTPResponse(statusCode: 200, data: Data())
            ]
        )
        let model = AppModel(
            settingsStore: settings,
            startMonitoring: false,
            openClawClient: OpenClawHookClient(
                transport: transport,
                retryPolicy: OpenClawRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 0)
            )
        )

        model.handle(snapshot: snapshot(remaining: 100, fiveHourRemaining: 62))
        model.handle(snapshot: snapshot(remaining: 78, fiveHourRemaining: 62))
        try await waitForRequestCount(3, on: transport)
        model.handle(snapshot: snapshot(remaining: 78, fiveHourRemaining: 62))
        try await waitForRequestCount(4, on: transport)

        let messages = await transport.messageValues()
        XCTAssertTrue(messages.last?.contains("80%") == true)
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 4)
        defaults.removePersistentDomain(forName: "CodexQuotaNotchTests.app-model-openclaw-retry")
    }

    private func addressedOpenClawSettings() -> OpenClawPushSettings {
        OpenClawPushSettings(
            enabled: true,
            gatewayURL: "http://127.0.0.1:18789",
            channel: "openclaw-weixin",
            target: "wechat-peer",
            accountID: "default"
        )
    }

    private func snapshot(
        remaining: Int,
        fiveHourRemaining: Int? = nil,
        fiveHourReset: Date = Date(timeIntervalSince1970: 1_787_320_800)
    ) -> QuotaSnapshot {
        let reset = Date().addingTimeInterval(7 * 24 * 60 * 60)
        return QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(windowMinutes: 10_080, usedPercent: Double(100 - remaining), resetsAt: reset),
            secondaryLimit: fiveHourRemaining.map {
                RateLimitSnapshot(
                    windowMinutes: 300,
                    usedPercent: Double(100 - $0),
                    resetsAt: fiveHourReset
                )
            },
            dailyTokens: 100,
            lastUpdatedAt: Date(),
            sourceStatus: .ready
        )
    }

    private func waitForRequestCount(
        _ expected: Int,
        on transport: AppModelRecordingTransport
    ) async throws {
        for _ in 0..<100 {
            if await transport.requestCount() >= expected {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for \(expected) OpenClaw request(s)")
    }
}

private final class InMemoryAppModelSecretStore: SecretStore {
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

private actor AppModelRecordingTransport: OpenClawTransport {
    private(set) var requests: [URLRequest] = []
    private(set) var messageValuesStorage: [String] = []
    private var responses: [OpenClawHTTPResponse]

    init(responses: [OpenClawHTTPResponse]) {
        self.responses = responses
    }

    func perform(_ request: URLRequest) async throws -> OpenClawHTTPResponse {
        requests.append(request)
        if let body = request.httpBody,
           let payload = try? JSONDecoder().decode(OpenClawHookPayload.self, from: body) {
            messageValuesStorage.append(payload.message)
        }
        if responses.isEmpty {
            return OpenClawHTTPResponse(statusCode: 200, data: Data())
        }
        return responses.removeFirst()
    }

    func requestCount() -> Int {
        requests.count
    }

    func messageValues() -> [String] {
        messageValuesStorage
    }
}
