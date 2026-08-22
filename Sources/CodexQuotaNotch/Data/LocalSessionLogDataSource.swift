import Foundation

public enum LocalSessionDataError: Error, Equatable {
    case rootDirectoryUnavailable(URL)
}

/// Reads Codex's JSONL session logs without materializing the log directory in memory.
///
/// Session files are append-only in normal operation. The cache therefore keeps only a
/// small summary for each file and resumes from the last complete line on the next scan.
/// A file is re-read from the beginning when it is replaced, truncated, or modified in
/// place. Calls are protected because the monitor owns this object across refreshes.
public final class LocalSessionLogDataSource: @unchecked Sendable {
    // The UI exposes seven days; one extra day preserves the boundary for a weekly window.
    private static let recentHistoryDays = 8

    public let rootDirectory: URL

    private let stateLock = NSLock()
    private var fileCache: [URL: CachedFile] = [:]
    private var calendarSignature: CalendarSignature?

    // Internal diagnostics used by regression tests to prove that refreshes are incremental.
    internal private(set) var lastReadBytes: UInt64 = 0

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func readSnapshot(now: Date = Date(), calendar: Calendar = .current) throws -> QuotaSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }

        lastReadBytes = 0
        resetCacheIfCalendarChanged(to: calendar)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalSessionDataError.rootDirectoryUnavailable(rootDirectory)
        }

        let files = try jsonlFiles().filter {
            isWithinRecentHistory($0, now: now, calendar: calendar)
        }
        let activeURLs = Set(files.map(\.url))
        fileCache = fileCache.filter { activeURLs.contains($0.key) }

        let parser = JSONLSessionParser()
        for file in files {
            updateCache(for: file, parser: parser, calendar: calendar)
        }

        let summaries = fileCache.values.map(\.summary).filter(\.hasEvents)
        guard !summaries.isEmpty else {
            return waitingSnapshot
        }

        let latestUpdatedAt = summaries.compactMap(\.latestTimestamp).max()
        let weekly = latestLimit(from: summaries, secondary: false)
        let secondary = latestLimit(from: summaries, secondary: true)
        let dailyTotals = mergedDailyTotals(from: summaries)
        let today = calendar.startOfDay(for: now)

        let sourceStatus: DataSourceStatus
        if weekly == nil {
            sourceStatus = .missingWeeklyLimit
        } else if let latestUpdatedAt, now.timeIntervalSince(latestUpdatedAt) > 900 {
            sourceStatus = .stale(lastUpdated: latestUpdatedAt)
        } else {
            sourceStatus = .ready
        }

        return QuotaSnapshot(
            weeklyLimit: weekly,
            secondaryLimit: secondary,
            dailyTokens: dailyTotals[today, default: 0],
            dailyTotals: dailyTotals,
            lastUpdatedAt: latestUpdatedAt,
            sourceStatus: sourceStatus
        )
    }

    private var waitingSnapshot: QuotaSnapshot {
        QuotaSnapshot(
            weeklyLimit: nil,
            secondaryLimit: nil,
            dailyTokens: 0,
            dailyTotals: [:],
            lastUpdatedAt: nil,
            sourceStatus: .waitingForSession
        )
    }

    private func resetCacheIfCalendarChanged(to calendar: Calendar) {
        let newSignature = CalendarSignature(calendar: calendar)
        guard calendarSignature != newSignature else { return }
        calendarSignature = newSignature
        fileCache.removeAll(keepingCapacity: true)
    }

    private func isWithinRecentHistory(
        _ record: FileRecord,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(
            byAdding: .day,
            value: -Self.recentHistoryDays,
            to: today
        ) ?? today

        if let sessionDay = sessionDay(for: record.url, calendar: calendar) {
            return sessionDay >= cutoff
        }

        // Custom data directories may not use Codex's YYYY/MM/DD layout. In that
        // case the file's modification date is the safest bounded approximation.
        return record.metadata.modificationDate.map { $0 >= cutoff } ?? true
    }

    private func sessionDay(for url: URL, calendar: Calendar) -> Date? {
        let components = url.pathComponents
        guard components.count >= 3 else { return nil }

        for index in 0..<(components.count - 2) {
            guard let year = Int(components[index]), year >= 2_000,
                  let month = Int(components[index + 1]), (1...12).contains(month),
                  let day = Int(components[index + 2]), (1...31).contains(day) else {
                continue
            }

            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            dateComponents.day = day
            guard let date = calendar.date(from: dateComponents) else { continue }
            return calendar.startOfDay(for: date)
        }

        return nil
    }

    private func updateCache(for record: FileRecord, parser: JSONLSessionParser, calendar: Calendar) {
        let cached = fileCache[record.url]

        if let cached, canReuse(cached, for: record) {
            var refreshed = cached
            refreshed.metadata = record.metadata
            fileCache[record.url] = refreshed
            return
        }

        let shouldAppend = cached.map { cachedFile in
            self.canAppend(to: cachedFile, for: record)
        } ?? false
        var summary = shouldAppend ? cached!.summary : FileSummary()
        let startingOffset = shouldAppend ? cached!.offset : 0

        guard let firstRead = read(
            record.url,
            startingAt: startingOffset,
            parser: parser,
            calendar: calendar,
            summary: &summary
        ) else {
            return
        }
        lastReadBytes += firstRead.bytesRead

        if firstRead.sawOutOfOrderEvent {
            summary = FileSummary()
            guard let rebuilt = read(
                record.url,
                startingAt: 0,
                parser: parser,
                calendar: calendar,
                summary: &summary
            ) else {
                return
            }
            lastReadBytes += rebuilt.bytesRead
            fileCache[record.url] = CachedFile(
                metadata: record.metadata,
                offset: rebuilt.completedOffset,
                summary: summary
            )
            return
        }

        fileCache[record.url] = CachedFile(
            metadata: record.metadata,
            offset: firstRead.completedOffset,
            summary: summary
        )
    }

    private func canReuse(_ cached: CachedFile, for record: FileRecord) -> Bool {
        guard sameFile(cached.metadata, record.metadata) else { return false }
        return cached.metadata.size == record.metadata.size
            && cached.metadata.modificationDate == record.metadata.modificationDate
    }

    private func canAppend(to cached: CachedFile, for record: FileRecord) -> Bool {
        guard sameFile(cached.metadata, record.metadata) else { return false }
        guard record.metadata.size >= cached.metadata.size,
              record.metadata.size >= cached.offset else { return false }

        // A size increase is the normal append-only case. If only the timestamp
        // changed, rebuild so an in-place edit cannot leave stale quota data behind.
        return record.metadata.size > cached.metadata.size
    }

    private func sameFile(_ lhs: FileMetadata, _ rhs: FileMetadata) -> Bool {
        guard let lhsFileNumber = lhs.fileNumber, let rhsFileNumber = rhs.fileNumber else {
            return true
        }
        return lhsFileNumber == rhsFileNumber
    }

    private func read(
        _ url: URL,
        startingAt offset: UInt64,
        parser: JSONLSessionParser,
        calendar: Calendar,
        summary: inout FileSummary
    ) -> StreamReadResult? {
        do {
            return try JSONLStreamReader().read(
                url: url,
                startingAt: offset,
                parser: parser,
                calendar: calendar,
                summary: &summary
            )
        } catch {
            return nil
        }
    }

    private func latestLimit(
        from summaries: [FileSummary],
        secondary: Bool
    ) -> RateLimitSnapshot? {
        summaries
            .compactMap { secondary ? $0.latestSecondary : $0.latestWeekly }
            .max(by: { $0.timestamp < $1.timestamp })?
            .snapshot
    }

    private func mergedDailyTotals(from summaries: [FileSummary]) -> [Date: Int] {
        summaries.reduce(into: [Date: Int]()) { result, summary in
            for (day, total) in summary.dailyTotals {
                result[day, default: 0] += total
            }
        }
    }

    private func jsonlFiles() throws -> [FileRecord] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension.lowercased() == "jsonl",
                  let metadata = FileMetadata(url: url),
                  metadata.isRegularFile else {
                return nil
            }
            return FileRecord(url: url, metadata: metadata)
        }
    }
}

private struct JSONLStreamReader {
    private static let chunkSize = 256 * 1024

    func read(
        url: URL,
        startingAt offset: UInt64,
        parser: JSONLSessionParser,
        calendar: Calendar,
        summary: inout FileSummary
    ) throws -> StreamReadResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)

        var buffer = Data()
        var completedOffset = offset
        var bytesRead: UInt64 = 0
        var sawOutOfOrderEvent = false

        while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            bytesRead += UInt64(chunk.count)
            buffer.append(contentsOf: chunk)

            var processedBytes = 0
            while let newline = buffer[processedBytes...].firstIndex(of: 0x0A) {
                var line = Data(buffer[processedBytes..<newline])
                if line.last == 0x0D {
                    line.removeLast()
                }

                if !line.isEmpty, let event = parser.parseLine(line) {
                    sawOutOfOrderEvent = summary.consume(event, calendar: calendar) || sawOutOfOrderEvent
                }

                processedBytes = newline + 1
            }

            if processedBytes > 0 {
                buffer.removeSubrange(0..<processedBytes)
                completedOffset += UInt64(processedBytes)
            }
        }

        return StreamReadResult(
            completedOffset: completedOffset,
            bytesRead: bytesRead,
            sawOutOfOrderEvent: sawOutOfOrderEvent
        )
    }
}

private struct StreamReadResult {
    let completedOffset: UInt64
    let bytesRead: UInt64
    let sawOutOfOrderEvent: Bool
}

private struct FileRecord {
    let url: URL
    let metadata: FileMetadata
}

private struct FileMetadata {
    let isRegularFile: Bool
    let size: UInt64
    let modificationDate: Date?
    let fileNumber: UInt64?

    init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let rawSize = attributes[.size] as? NSNumber
        let rawFileNumber = attributes[.systemFileNumber] as? NSNumber
        isRegularFile = (attributes[.type] as? FileAttributeType) == .typeRegular
        size = rawSize?.uint64Value ?? 0
        modificationDate = attributes[.modificationDate] as? Date
        fileNumber = rawFileNumber?.uint64Value
    }
}

private struct CachedFile {
    var metadata: FileMetadata
    let offset: UInt64
    let summary: FileSummary
}

private struct TimedRateLimit {
    let timestamp: Date
    let snapshot: RateLimitSnapshot
}

private struct FileSummary {
    var latestTimestamp: Date?
    var latestWeekly: TimedRateLimit?
    var latestSecondary: TimedRateLimit?
    var dailyTotals: [Date: Int] = [:]
    var previousTokenTotal = 0
    var lastEventTimestamp: Date?
    var hasEvents = false

    mutating func consume(_ event: ParsedSessionEvent, calendar: Calendar) -> Bool {
        let sawOutOfOrderEvent = lastEventTimestamp.map { event.timestamp < $0 } ?? false
        latestTimestamp = max(latestTimestamp ?? event.timestamp, event.timestamp)
        lastEventTimestamp = event.timestamp
        hasEvents = true

        for snapshot in event.rateLimits {
            let timedLimit = TimedRateLimit(timestamp: event.timestamp, snapshot: snapshot)
            if snapshot.windowMinutes == 10_080 {
                if latestWeekly == nil || timedLimit.timestamp >= latestWeekly!.timestamp {
                    latestWeekly = timedLimit
                }
            } else if latestSecondary == nil || timedLimit.timestamp >= latestSecondary!.timestamp {
                latestSecondary = timedLimit
            }
        }

        guard event.kind == .tokenCount else { return sawOutOfOrderEvent }

        let current = DailyUsageAggregator.effectiveTokenTotal(for: event)
        guard current >= previousTokenTotal else { return sawOutOfOrderEvent }

        let day = calendar.startOfDay(for: event.timestamp)
        dailyTotals[day, default: 0] += current - previousTokenTotal
        previousTokenTotal = current
        return sawOutOfOrderEvent
    }
}

private struct CalendarSignature: Equatable {
    let identifier: Calendar.Identifier
    let timeZoneIdentifier: String

    init(calendar: Calendar) {
        identifier = calendar.identifier
        timeZoneIdentifier = calendar.timeZone.identifier
    }
}
