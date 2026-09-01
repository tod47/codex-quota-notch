import XCTest
@testable import CodexQuotaNotch

final class QuotaMonitorTests: XCTestCase {
    func testRefreshGateCoalescesRequestsUntilTheRefreshCompletes() {
        var gate = RefreshGate()

        XCTAssertTrue(gate.request())
        XCTAssertFalse(gate.request())

        gate.complete()

        XCTAssertTrue(gate.request())
    }

    func testManualRefreshCompletesEvenWhenAutomaticRefreshIsPending() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaNotchTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("session.jsonl")
        let contents = """
        {"timestamp":"2026-08-17T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"primary":{"window_minutes":10080,"used_percent":10,"resets_at":1787306400}}}}
        """
        try Data(contents.utf8).write(to: file)

        let source = LocalSessionLogDataSource(rootDirectory: directory)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_786_903_500)
        _ = try source.readSnapshot(now: now, calendar: calendar)
        _ = try source.readSnapshot(now: now, calendar: calendar)
        XCTAssertEqual(source.lastReadBytes, 0, "The test should start from a populated cache")

        let monitor = QuotaMonitor(
            dataSource: source,
            calendar: calendar,
            now: { now },
            onSnapshot: { _ in }
        )
        let completion = expectation(description: "manual refresh completes")
        monitor.start()
        monitor.refreshNow {
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)

        monitor.stop()
    }
}
