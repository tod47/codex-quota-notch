import Foundation

public enum ParsedEventKind: Equatable, Sendable {
    case tokenCount
    case other
}

public struct ParsedSessionEvent: Equatable, Sendable {
    public let timestamp: Date
    public let kind: ParsedEventKind
    public let rateLimits: [RateLimitSnapshot]
    public let lastUsage: UsageTotals?
    public let totalUsage: UsageTotals?

    public init(
        timestamp: Date,
        kind: ParsedEventKind,
        rateLimits: [RateLimitSnapshot],
        lastUsage: UsageTotals?,
        totalUsage: UsageTotals?
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.rateLimits = rateLimits
        self.lastUsage = lastUsage
        self.totalUsage = totalUsage
    }
}

public struct JSONLSessionParser: Sendable {
    public init() {}

    public func parseLine(_ data: Data) -> ParsedSessionEvent? {
        guard let envelope = try? JSONDecoder().decode(RawEnvelope.self, from: data),
              let timestamp = envelope.timestamp.date else {
            return nil
        }

        let limits = [envelope.payload.rateLimits?.primary, envelope.payload.rateLimits?.secondary]
            .compactMap { $0 }
            .compactMap { $0.snapshot }

        let kind: ParsedEventKind = envelope.type == "event_msg" && envelope.payload.type == "token_count"
            ? .tokenCount
            : .other

        return ParsedSessionEvent(
            timestamp: timestamp,
            kind: kind,
            rateLimits: limits,
            lastUsage: envelope.payload.info?.lastTokenUsage?.usage,
            totalUsage: envelope.payload.info?.totalTokenUsage?.usage
        )
    }
}

private struct RawEnvelope: Decodable {
    let timestamp: FlexibleDate
    let type: String
    let payload: RawPayload
}

private struct RawPayload: Decodable {
    let type: String?
    let info: RawInfo?
    let rateLimits: RawRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
    }
}

private struct RawInfo: Decodable {
    let lastTokenUsage: RawUsage?
    let totalTokenUsage: RawUsage?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

private struct RawUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let cacheWriteInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    var usage: UsageTotals {
        UsageTotals(
            inputTokens: inputTokens ?? 0,
            cachedInputTokens: cachedInputTokens ?? 0,
            cacheWriteInputTokens: cacheWriteInputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            reasoningOutputTokens: reasoningOutputTokens ?? 0,
            totalTokens: totalTokens ?? 0
        )
    }
}

private struct RawRateLimits: Decodable {
    let primary: RawRateLimit?
    let secondary: RawRateLimit?
}

private struct RawRateLimit: Decodable {
    let windowMinutes: Int?
    let usedPercent: Double?
    let resetsAt: FlexibleDate?
    let limitName: String?

    enum CodingKeys: String, CodingKey {
        case windowMinutes = "window_minutes"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case limitName = "limit_name"
    }

    var snapshot: RateLimitSnapshot? {
        guard let windowMinutes, let usedPercent else { return nil }
        return RateLimitSnapshot(
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            resetsAt: resetsAt?.date,
            name: limitName
        )
    }
}

private struct FlexibleDate: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let seconds = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds)
            return
        }

        if let string = try? container.decode(String.self) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
            return
        }

        date = nil
    }
}
