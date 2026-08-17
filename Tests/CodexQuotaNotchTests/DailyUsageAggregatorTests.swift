import Foundation
import XCTest
@testable import CodexQuotaNotch

final class DailyUsageAggregatorTests: XCTestCase {
    func testUsesPositiveCumulativeDeltasOnly() {
        XCTAssertEqual(DailyUsageAggregator.deltaTotal([1_000, 1_400, 1_400, 1_250, 1_900]), 1_900)
    }

    func testSplitsTotalsByLocalDate() {
        let calendar = fixedCalendar(timeZone: "Asia/Shanghai")
        let firstDay = date("2026-08-17T23:55:00+0800")
        let secondDay = date("2026-08-18T00:05:00+0800")
        let laterSecondDay = date("2026-08-18T00:30:00+0800")
        let events = [
            ParsedSessionEvent(timestamp: firstDay, kind: .tokenCount, rateLimits: [], lastUsage: nil, totalUsage: totals(1_000)),
            ParsedSessionEvent(timestamp: secondDay, kind: .tokenCount, rateLimits: [], lastUsage: nil, totalUsage: totals(1_400)),
            ParsedSessionEvent(timestamp: laterSecondDay, kind: .tokenCount, rateLimits: [], lastUsage: nil, totalUsage: totals(1_900))
        ]

        let result = DailyUsageAggregator().totals(eventsByFile: [URL(fileURLWithPath: "/session.jsonl"): events], calendar: calendar)

        XCTAssertEqual(result[calendar.startOfDay(for: firstDay)], 1_000)
        XCTAssertEqual(result[calendar.startOfDay(for: secondDay)], 900)
    }

    private func totals(_ value: Int) -> UsageTotals {
        UsageTotals(totalTokens: value)
    }

    private func fixedCalendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
