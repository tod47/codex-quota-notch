import Foundation
import XCTest
@testable import CodexQuotaNotch

@MainActor
final class OverlayViewTests: XCTestCase {
    func testFiveHourSectionVisibilityFollowsPreferenceAndData() {
        let resetDate = Date(timeIntervalSince1970: 1_735_689_600)
        let snapshot = QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(
                windowMinutes: 10_080,
                usedPercent: 20,
                resetsAt: resetDate
            ),
            secondaryLimit: RateLimitSnapshot(
                windowMinutes: 300,
                usedPercent: 25,
                resetsAt: resetDate
            ),
            dailyTokens: 0,
            lastUpdatedAt: resetDate,
            sourceStatus: .ready
        )

        XCTAssertTrue(
            OverlayView(snapshot: snapshot, showFiveHourQuota: true).shouldShowFiveHourQuota
        )
        XCTAssertFalse(
            OverlayView(snapshot: snapshot, showFiveHourQuota: false).shouldShowFiveHourQuota
        )
        XCTAssertFalse(
            OverlayView(
                snapshot: QuotaSnapshot(
                    weeklyLimit: snapshot.weeklyLimit,
                    secondaryLimit: nil,
                    dailyTokens: 0,
                    lastUpdatedAt: resetDate,
                    sourceStatus: .ready
                ),
                showFiveHourQuota: true
            ).shouldShowFiveHourQuota
        )
    }

    func testStaleDataExposesARefreshAction() {
        let resetDate = Date(timeIntervalSince1970: 1_735_689_600)
        let snapshot = QuotaSnapshot(
            weeklyLimit: RateLimitSnapshot(
                windowMinutes: 10_080,
                usedPercent: 20,
                resetsAt: resetDate
            ),
            secondaryLimit: nil,
            dailyTokens: 0,
            lastUpdatedAt: resetDate,
            sourceStatus: .stale(lastUpdated: resetDate)
        )
        var refreshCount = 0

        let view = OverlayView(
            snapshot: snapshot,
            onRefresh: { refreshCount += 1 }
        )

        view.onRefresh?()

        XCTAssertEqual(refreshCount, 1)
    }
}
