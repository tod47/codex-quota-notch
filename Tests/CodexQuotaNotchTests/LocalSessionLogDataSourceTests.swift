import Foundation
import XCTest
@testable import CodexQuotaNotch

final class LocalSessionLogDataSourceTests: XCTestCase {
    func testReadsAppendsIncrementallyAndKeepsTheLatestQuota() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let firstLine = line(timestamp: "2026-08-17T02:00:00.000Z", usedPercent: 10, totalTokens: 100)
        try Data(firstLine.utf8).write(to: file)

        let source = LocalSessionLogDataSource(rootDirectory: directory)
        let calendar = fixedCalendar(timeZone: "UTC")
        let now = date("2026-08-17T02:05:00.000Z")

        let firstSnapshot = try source.readSnapshot(now: now, calendar: calendar)
        XCTAssertEqual(firstSnapshot.remainingPercent, 90)
        XCTAssertEqual(firstSnapshot.dailyTokens, 100)
        let firstReadBytes = source.lastReadBytes

        let secondLine = line(timestamp: "2026-08-17T02:01:00.000Z", usedPercent: 20, totalTokens: 250)
        try append(Data(secondLine.utf8), to: file)

        let secondSnapshot = try source.readSnapshot(now: now, calendar: calendar)
        XCTAssertEqual(secondSnapshot.remainingPercent, 80)
        XCTAssertEqual(secondSnapshot.dailyTokens, 250)
        XCTAssertEqual(secondSnapshot.dailyTotals[calendar.startOfDay(for: now)], 250)
        XCTAssertLessThan(source.lastReadBytes, firstReadBytes + UInt64(secondLine.utf8.count))

        _ = try source.readSnapshot(now: now, calendar: calendar)
        XCTAssertEqual(source.lastReadBytes, 0)
    }

    func testRebuildsAFileAfterItIsTruncated() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let original = line(timestamp: "2026-08-17T02:00:00.000Z", usedPercent: 10, totalTokens: 1_000)
            + line(timestamp: "2026-08-17T02:01:00.000Z", usedPercent: 20, totalTokens: 1_250)
        try Data(original.utf8).write(to: file)

        let source = LocalSessionLogDataSource(rootDirectory: directory)
        let calendar = fixedCalendar(timeZone: "UTC")
        let now = date("2026-08-17T02:05:00.000Z")
        XCTAssertEqual(try source.readSnapshot(now: now, calendar: calendar).dailyTokens, 1_250)

        let replacement = line(timestamp: "2026-08-17T02:02:00.000Z", usedPercent: 5, totalTokens: 40)
        try Data(replacement.utf8).write(to: file)

        let snapshot = try source.readSnapshot(now: now, calendar: calendar)
        XCTAssertEqual(snapshot.remainingPercent, 95)
        XCTAssertEqual(snapshot.dailyTokens, 40)
    }

    func testSkipsSessionFilesOutsideTheRecentQuotaWindow() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldDirectory = directory
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("08", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
        let recentDirectory = directory
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("08", isDirectory: true)
            .appendingPathComponent("17", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentDirectory, withIntermediateDirectories: true)

        try Data(line(timestamp: "2026-08-01T02:00:00.000Z", usedPercent: 99, totalTokens: 9_900).utf8)
            .write(to: oldDirectory.appendingPathComponent("old.jsonl"))
        try Data(line(timestamp: "2026-08-17T02:00:00.000Z", usedPercent: 10, totalTokens: 100).utf8)
            .write(to: recentDirectory.appendingPathComponent("recent.jsonl"))

        let source = LocalSessionLogDataSource(rootDirectory: directory)
        let calendar = fixedCalendar(timeZone: "UTC")
        let now = date("2026-08-17T02:05:00.000Z")
        let snapshot = try source.readSnapshot(now: now, calendar: calendar)

        XCTAssertEqual(snapshot.remainingPercent, 90)
        XCTAssertEqual(snapshot.dailyTokens, 100)
        XCTAssertEqual(snapshot.dailyTotals.count, 1)
    }

    func testKeepsTheFiveHourLimitWhenAnotherShortWindowIsNewer() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let contents = line(
            timestamp: "2026-08-17T02:00:00.000Z",
            usedPercent: 10,
            totalTokens: 100,
            shortWindowMinutes: 300,
            shortUsedPercent: 25
        ) + line(
            timestamp: "2026-08-17T02:01:00.000Z",
            usedPercent: 20,
            totalTokens: 250,
            shortWindowMinutes: 60,
            shortUsedPercent: 99
        )
        try Data(contents.utf8).write(to: file)

        let source = LocalSessionLogDataSource(rootDirectory: directory)
        let calendar = fixedCalendar(timeZone: "UTC")
        let now = date("2026-08-17T02:05:00.000Z")
        let snapshot = try source.readSnapshot(now: now, calendar: calendar)

        XCTAssertEqual(snapshot.secondaryLimit?.windowMinutes, 300)
        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 75)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaNotchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func line(
        timestamp: String,
        usedPercent: Int,
        totalTokens: Int,
        shortWindowMinutes: Int? = nil,
        shortUsedPercent: Int = 0
    ) -> String {
        let secondary = shortWindowMinutes.map {
            ",\"secondary\":{\"window_minutes\":\($0),\"used_percent\":\(shortUsedPercent),\"resets_at\":1787306400,\"limit_name\":\"short\"}"
        } ?? ""
        return """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(totalTokens)}},"rate_limits":{"primary":{"window_minutes":10080,"used_percent":\(usedPercent),"resets_at":1787306400,"limit_name":"weekly"}\(secondary)}}}\n
        """
    }

    private func fixedCalendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}
