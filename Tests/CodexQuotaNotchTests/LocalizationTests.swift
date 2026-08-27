import Foundation
import XCTest
@testable import CodexQuotaNotch

final class LocalizationTests: XCTestCase {
    func testApprovedChineseAlertCopyIsPresent() throws {
        let url = try XCTUnwrap(L10n.stringsURL(forLanguage: "zh-Hans"))
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("距离 Codex 周额度重置只剩下 2 天"))
        XCTAssertTrue(contents.contains("距离 Codex 周额度重置只剩下一天"))
        XCTAssertTrue(contents.contains("距离 Codex 周额度将在 5 小时后重置"))
        XCTAssertTrue(contents.contains("Codex 周额度已重置"))
        XCTAssertTrue(contents.contains("Codex 周额度已用尽"))
    }

    @MainActor
    func testExplicitLanguageLoadsRequestedStrings() {
        XCTAssertEqual(L10n.text("overview", language: .english), "Overview")
        XCTAssertEqual(L10n.text("overview", language: .chineseSimplified), "总览")
        XCTAssertEqual(L10n.text("alerts", language: .english), "Alerts")
        XCTAssertEqual(L10n.text("alerts", language: .chineseSimplified), "提醒")
        XCTAssertEqual(L10n.text("top.popup", language: .english), "Top popup")
        XCTAssertEqual(L10n.text("top.popup", language: .chineseSimplified), "顶部弹窗")
        XCTAssertEqual(L10n.text("quota.weekly", language: .english), "Weekly quota")
        XCTAssertEqual(L10n.text("quota.weekly", language: .chineseSimplified), "周额度")
        XCTAssertEqual(L10n.text("quota.five.hour", language: .english), "5-hour quota")
        XCTAssertEqual(L10n.text("quota.five.hour", language: .chineseSimplified), "5 小时额度")
        XCTAssertEqual(L10n.text("show.five.hour.quota", language: .english), "Show 5-hour quota")
        XCTAssertEqual(L10n.text("show.five.hour.quota", language: .chineseSimplified), "显示 5 小时额度")
    }
}
