import Foundation

public enum LocalSessionDataError: Error, Equatable {
    case rootDirectoryUnavailable(URL)
}

public struct LocalSessionLogDataSource: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func readSnapshot(now: Date = Date(), calendar: Calendar = .current) throws -> QuotaSnapshot {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalSessionDataError.rootDirectoryUnavailable(rootDirectory)
        }

        let files = try jsonlFiles()
        guard !files.isEmpty else {
            return QuotaSnapshot(
                weeklyLimit: nil,
                secondaryLimit: nil,
                dailyTokens: 0,
                lastUpdatedAt: nil,
                sourceStatus: .waitingForSession
            )
        }

        var eventsByFile: [URL: [ParsedSessionEvent]] = [:]
        let parser = JSONLSessionParser()

        for file in files {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let events = contents
                .split(whereSeparator: \.isNewline)
                .compactMap { parser.parseLine(Data($0.utf8)) }
            if !events.isEmpty {
                eventsByFile[file] = events
            }
        }

        guard !eventsByFile.isEmpty else {
            return QuotaSnapshot(
                weeklyLimit: nil,
                secondaryLimit: nil,
                dailyTokens: 0,
                lastUpdatedAt: nil,
                sourceStatus: .waitingForSession
            )
        }

        let allEvents = eventsByFile.values.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
        let latestUpdatedAt = allEvents.last?.timestamp
        let allLimits = allEvents.flatMap(\.rateLimits)
        let weekly = allLimits.last(where: { $0.windowMinutes == 10_080 })
        let secondary = allLimits.last(where: { $0.windowMinutes != 10_080 })
        let dailyTotals = DailyUsageAggregator().totals(eventsByFile: eventsByFile, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let dailyTokens = dailyTotals[today, default: 0]

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
            dailyTokens: dailyTokens,
            lastUpdatedAt: latestUpdatedAt,
            sourceStatus: sourceStatus
        )
    }

    private func jsonlFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension.lowercased() == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }
    }
}
