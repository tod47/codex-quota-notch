import Foundation

public struct DailyUsageAggregator: Sendable {
    public init() {}

    public static func deltaTotal(_ values: [Int]) -> Int {
        var previous = 0
        var total = 0

        for value in values {
            guard value >= previous else { continue }
            total += value - previous
            previous = value
        }

        return total
    }

    public func totals(
        eventsByFile: [URL: [ParsedSessionEvent]],
        calendar: Calendar
    ) -> [Date: Int] {
        var result: [Date: Int] = [:]

        for events in eventsByFile.values {
            var previous = 0
            for event in events.sorted(by: { $0.timestamp < $1.timestamp }) where event.kind == .tokenCount {
                let current = effectiveTokenTotal(for: event)
                guard current >= 0 else { continue }

                if current >= previous {
                    let delta = current - previous
                    let day = calendar.startOfDay(for: event.timestamp)
                    result[day, default: 0] += delta
                    previous = current
                }
            }
        }

        return result
    }

    private func effectiveTokenTotal(for event: ParsedSessionEvent) -> Int {
        if let totalUsage = event.totalUsage, totalUsage.effectiveTotal > 0 {
            return totalUsage.effectiveTotal
        }
        return event.lastUsage?.effectiveTotal ?? 0
    }
}
