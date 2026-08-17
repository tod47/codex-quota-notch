import Foundation

public enum QuotaMath {
    public static func remainingPercent(fromUsedPercent value: Double) -> Int {
        Int(floor(min(100, max(0, 100 - value))))
    }

    public static func cycleID(for resetDate: Date?) -> String? {
        resetDate.map { String(Int($0.timeIntervalSince1970)) }
    }
}

public struct RateLimitSnapshot: Equatable, Sendable {
    public let windowMinutes: Int
    public let usedPercent: Double
    public let resetsAt: Date?
    public let name: String?

    public init(windowMinutes: Int, usedPercent: Double, resetsAt: Date?, name: String? = nil) {
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.name = name
    }
}

public struct UsageTotals: Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public var componentTotal: Int {
        inputTokens + cachedInputTokens + cacheWriteInputTokens + outputTokens + reasoningOutputTokens
    }

    public var effectiveTotal: Int {
        totalTokens > 0 ? totalTokens : componentTotal
    }
}

public enum DataSourceStatus: Equatable, Sendable {
    case ready
    case waitingForSession
    case missingWeeklyLimit
    case stale(lastUpdated: Date)
    case unreadable(String)
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let weeklyLimit: RateLimitSnapshot?
    public let secondaryLimit: RateLimitSnapshot?
    public let dailyTokens: Int
    public let dailyTotals: [Date: Int]
    public let lastUpdatedAt: Date?
    public let sourceStatus: DataSourceStatus

    public init(
        weeklyLimit: RateLimitSnapshot?,
        secondaryLimit: RateLimitSnapshot?,
        dailyTokens: Int,
        dailyTotals: [Date: Int] = [:],
        lastUpdatedAt: Date?,
        sourceStatus: DataSourceStatus
    ) {
        self.weeklyLimit = weeklyLimit
        self.secondaryLimit = secondaryLimit
        self.dailyTokens = dailyTokens
        self.dailyTotals = dailyTotals
        self.lastUpdatedAt = lastUpdatedAt
        self.sourceStatus = sourceStatus
    }

    public var remainingPercent: Int? {
        weeklyLimit.map { QuotaMath.remainingPercent(fromUsedPercent: $0.usedPercent) }
    }

    public var resetsAt: Date? {
        weeklyLimit?.resetsAt
    }

    public var cycleID: String? {
        QuotaMath.cycleID(for: resetsAt)
    }
}
