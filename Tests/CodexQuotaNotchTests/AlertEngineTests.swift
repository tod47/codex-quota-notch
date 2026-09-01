import Foundation
import XCTest
@testable import CodexQuotaNotch

final class AlertEngineTests: XCTestCase {
    private let engine = AlertEngine()
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let resetDate = Date(timeIntervalSince1970: 1_750_604_800)

    func testTenPercentCrossingEmitsOnlyCurrentThreshold() {
        let result = engine.evaluate(
            previous: snapshot(remaining: 100, reset: resetDate),
            current: snapshot(remaining: 78, reset: resetDate),
            now: now,
            settings: .defaults,
            state: .empty
        )

        XCTAssertEqual(result.alerts.map(\.kind), [.percentage(80)])
    }

    func testDoesNotEmitPercentageForInitialSnapshotBelowThreshold() {
        let result = engine.evaluate(
            previous: nil,
            current: snapshot(remaining: 73, reset: resetDate),
            now: now,
            settings: .defaults,
            state: .empty
        )

        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testDoesNotEmitPercentageWhenCurrentValueStaysWithinThresholdBand() {
        let result = engine.evaluate(
            previous: snapshot(remaining: 74, reset: resetDate),
            current: snapshot(remaining: 73, reset: resetDate),
            now: now,
            settings: .defaults,
            state: .empty
        )

        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testCriticalZoneEmitsEachPercentOnce() {
        var state = AlertState.empty
        let first = engine.evaluate(
            previous: snapshot(remaining: 12, reset: resetDate),
            current: snapshot(remaining: 9, reset: resetDate),
            now: now,
            settings: .defaults,
            state: state
        )
        state = first.updatedState

        let repeated = engine.evaluate(
            previous: snapshot(remaining: 9, reset: resetDate),
            current: snapshot(remaining: 9, reset: resetDate),
            now: now,
            settings: .defaults,
            state: state
        )

        XCTAssertEqual(first.alerts.map(\.kind), [.percentage(9)])
        XCTAssertTrue(repeated.alerts.isEmpty)
    }

    func testCountdownUsesMostImmediateWindow() {
        let currentTime = resetDate.addingTimeInterval(-3 * 60 * 60)
        let result = engine.evaluate(
            previous: snapshot(remaining: 72, reset: resetDate),
            current: snapshot(remaining: 72, reset: resetDate),
            now: currentTime,
            settings: .defaults,
            state: .empty
        )

        XCTAssertEqual(result.alerts.map(\.kind), [.countdown(hours: 5)])
    }

    func testResetClearsPreviousCycleAndEmitsReset() {
        let oldReset = resetDate
        let newReset = resetDate.addingTimeInterval(7 * 24 * 60 * 60)
        let state = AlertState(cycleID: QuotaMath.cycleID(for: oldReset), emittedKeys: ["percentage:80"])

        let result = engine.evaluate(
            previous: snapshot(remaining: 20, reset: oldReset),
            current: snapshot(remaining: 100, reset: newReset),
            now: now,
            settings: .defaults,
            state: state
        )

        XCTAssertEqual(result.alerts.map(\.kind), [.reset])
        XCTAssertEqual(result.updatedState.cycleID, QuotaMath.cycleID(for: newReset))
        XCTAssertTrue(result.updatedState.emittedKeys.contains("reset"))
        XCTAssertFalse(result.updatedState.emittedKeys.contains("percentage:80"))
    }

    func testResetTimestampJitterDoesNotEmitReset() {
        let state = AlertState(cycleID: QuotaMath.cycleID(for: resetDate))

        let result = engine.evaluate(
            previous: snapshot(remaining: 72, reset: resetDate),
            current: snapshot(remaining: 72, reset: resetDate.addingTimeInterval(30)),
            now: now,
            settings: .defaults,
            state: state
        )

        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.updatedState.cycleID, state.cycleID)
    }

    func testLegacyCycleIDDoesNotEmitResetAfterNormalization() {
        let legacyCycleID = String(Int(resetDate.timeIntervalSince1970))
        let state = AlertState(cycleID: legacyCycleID)

        let result = engine.evaluate(
            previous: snapshot(remaining: 72, reset: resetDate),
            current: snapshot(remaining: 72, reset: resetDate.addingTimeInterval(30)),
            now: now,
            settings: .defaults,
            state: state
        )

        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.updatedState.cycleID, QuotaMath.cycleID(for: resetDate))
    }

    func testExhaustedHasPriorityOverCountdown() {
        let almostReset = now.addingTimeInterval(60 * 60)
        let result = engine.evaluate(
            previous: snapshot(remaining: 1, reset: almostReset),
            current: snapshot(remaining: 0, reset: almostReset),
            now: now,
            settings: .defaults,
            state: .empty
        )

        XCTAssertEqual(result.alerts.map(\.kind), [.exhausted])
    }

    private func snapshot(remaining: Int, reset: Date) -> QuotaSnapshot {
        let weekly = RateLimitSnapshot(
            windowMinutes: 10_080,
            usedPercent: Double(100 - remaining),
            resetsAt: reset
        )
        return QuotaSnapshot(
            weeklyLimit: weekly,
            secondaryLimit: nil,
            dailyTokens: 0,
            lastUpdatedAt: now,
            sourceStatus: .ready
        )
    }
}
