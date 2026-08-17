import Foundation
import XCTest
@testable import CodexQuotaNotch

final class JSONLSessionParserTests: XCTestCase {
    func testParsesSevenDayRateLimitAndTokenUsage() throws {
        let event = try XCTUnwrap(loadEvents(named: "session-standard").first(where: { $0.kind == .tokenCount }))

        XCTAssertEqual(event.rateLimits.first?.windowMinutes, 10_080)
        XCTAssertEqual(event.rateLimits.first?.usedPercent, 20)
        XCTAssertEqual(event.lastUsage?.totalTokens, 2_400)
        XCTAssertEqual(event.totalUsage?.totalTokens, 2_400)
    }

    func testSkipsMalformedLinesButKeepsValidEvents() {
        let events = loadEvents(named: "session-malformed")

        XCTAssertEqual(events.filter { $0.kind == .tokenCount }.count, 1)
    }

    func testKeepsValidTokenEventWhenWeeklyLimitIsMissing() throws {
        let event = try XCTUnwrap(loadEvents(named: "session-missing-fields").first(where: { $0.kind == .tokenCount }))

        XCTAssertTrue(event.rateLimits.allSatisfy { $0.windowMinutes != 10_080 })
        XCTAssertEqual(event.lastUsage?.totalTokens, 600)
    }

    private func loadEvents(named name: String) -> [ParsedSessionEvent] {
        let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
        let contents = try! String(contentsOf: url, encoding: .utf8)
        let parser = JSONLSessionParser()

        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { parser.parseLine(Data($0.utf8)) }
    }
}
