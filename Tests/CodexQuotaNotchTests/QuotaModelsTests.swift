import XCTest
@testable import CodexQuotaNotch

final class QuotaModelsTests: XCTestCase {
    func testRemainingPercentClampsAndFloors() {
        XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: 10.1), 89)
        XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: -2), 100)
        XCTAssertEqual(QuotaMath.remainingPercent(fromUsedPercent: 120), 0)
    }

    func testCycleIDUsesResetDate() {
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        XCTAssertEqual(QuotaMath.cycleID(for: date), "1735689600")
    }

    func testSnapshotDerivesRemainingPercentFromWeeklyLimit() {
        let resetDate = Date(timeIntervalSince1970: 1_735_689_600)
        let weekly = RateLimitSnapshot(
            windowMinutes: 10_080,
            usedPercent: 20,
            resetsAt: resetDate,
            name: "Weekly"
        )
        let snapshot = QuotaSnapshot(
            weeklyLimit: weekly,
            secondaryLimit: nil,
            dailyTokens: 1_200,
            lastUpdatedAt: resetDate,
            sourceStatus: .ready
        )

        XCTAssertEqual(snapshot.remainingPercent, 80)
        XCTAssertEqual(snapshot.cycleID, "1735689600")
    }

    func testSnapshotExposesOnlyTheFiveHourLimitAsFiveHourQuota() {
        let resetDate = Date(timeIntervalSince1970: 1_735_689_600)
        let fiveHour = RateLimitSnapshot(
            windowMinutes: 300,
            usedPercent: 25,
            resetsAt: resetDate,
            name: "5h"
        )
        let otherShortLimit = RateLimitSnapshot(
            windowMinutes: 60,
            usedPercent: 40,
            resetsAt: resetDate,
            name: "Hourly"
        )

        let fiveHourSnapshot = QuotaSnapshot(
            weeklyLimit: nil,
            secondaryLimit: fiveHour,
            dailyTokens: 0,
            lastUpdatedAt: resetDate,
            sourceStatus: .ready
        )
        let otherShortLimitSnapshot = QuotaSnapshot(
            weeklyLimit: nil,
            secondaryLimit: otherShortLimit,
            dailyTokens: 0,
            lastUpdatedAt: resetDate,
            sourceStatus: .ready
        )

        XCTAssertEqual(fiveHourSnapshot.fiveHourLimit, fiveHour)
        XCTAssertEqual(fiveHourSnapshot.fiveHourRemainingPercent, 75)
        XCTAssertNil(otherShortLimitSnapshot.fiveHourLimit)
        XCTAssertNil(otherShortLimitSnapshot.fiveHourRemainingPercent)
    }

    func testDefaultAlertSettingsMatchApprovedBehavior() {
        let settings = AlertSettings.defaults

        XCTAssertEqual(settings.ordinaryStep, 10)
        XCTAssertEqual(settings.criticalStart, 10)
        XCTAssertEqual(settings.criticalStep, 1)
        XCTAssertEqual(settings.countdownHours, [48, 24, 5])
        XCTAssertTrue(settings.overlayAlertsEnabled)
        XCTAssertTrue(settings.systemNotificationsEnabled)
    }
}
