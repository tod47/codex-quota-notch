import Foundation

public struct OpenClawHookPayload: Codable, Equatable, Sendable {
    public let name: String
    public let message: String
    public let deliver: Bool
    public let channel: String
    public let to: String
    public let accountID: String?

    public init(
        name: String = "codex-quota-notch",
        message: String,
        deliver: Bool = true,
        channel: String,
        to: String,
        accountID: String? = nil
    ) {
        self.name = name
        self.message = message
        self.deliver = deliver
        self.channel = channel
        self.to = to
        self.accountID = accountID
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case message
        case deliver
        case channel
        case to
        case accountID = "accountId"
    }
}

public struct OpenClawHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol OpenClawTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> OpenClawHTTPResponse
}

public struct URLSessionOpenClawTransport: OpenClawTransport {
    public init() {}

    public func perform(_ request: URLRequest) async throws -> OpenClawHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenClawHookClientError.invalidResponse
        }
        return OpenClawHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

public struct OpenClawRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelayNanoseconds: UInt64

    public init(maxAttempts: Int = 3, baseDelayNanoseconds: UInt64 = 500_000_000) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelayNanoseconds = baseDelayNanoseconds
    }
}

public enum OpenClawHookClientError: Error, Equatable {
    case disabled
    case invalidGatewayURL
    case missingToken
    case missingChannel
    case missingTarget
    case invalidResponse
    case httpStatus(Int)
}

public final class OpenClawHookClient: @unchecked Sendable {
    private let transport: any OpenClawTransport
    private let retryPolicy: OpenClawRetryPolicy

    public init(
        transport: any OpenClawTransport = URLSessionOpenClawTransport(),
        retryPolicy: OpenClawRetryPolicy = OpenClawRetryPolicy()
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    public func send(
        message: String,
        configuration: OpenClawPushSettings,
        token: String
    ) async throws {
        let request = try makeRequest(
            message: message,
            configuration: configuration,
            token: token
        )

        var attempt = 0
        while true {
            do {
                let response = try await transport.perform(request)
                guard (200..<300).contains(response.statusCode) else {
                    throw OpenClawHookClientError.httpStatus(response.statusCode)
                }
                return
            } catch {
                attempt += 1
                guard attempt < retryPolicy.maxAttempts else { throw error }
                let multiplier = UInt64(1 << min(attempt - 1, 20))
                let delay = retryPolicy.baseDelayNanoseconds.multipliedReportingOverflow(by: multiplier)
                if !delay.overflow && delay.partialValue > 0 {
                    try await Task.sleep(nanoseconds: delay.partialValue)
                }
            }
        }
    }

    private func makeRequest(
        message: String,
        configuration: OpenClawPushSettings,
        token: String
    ) throws -> URLRequest {
        guard configuration.enabled else { throw OpenClawHookClientError.disabled }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenClawHookClientError.missingToken
        }
        guard !configuration.channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenClawHookClientError.missingChannel
        }
        guard !configuration.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenClawHookClientError.missingTarget
        }
        guard let baseURL = URL(string: configuration.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil else {
            throw OpenClawHookClientError.invalidGatewayURL
        }

        let endpoint = baseURL
            .appendingPathComponent("hooks")
            .appendingPathComponent("agent")
        let payload = OpenClawHookPayload(
            message: message,
            channel: configuration.channel.trimmingCharacters(in: .whitespacesAndNewlines),
            to: configuration.target.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: configuration.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : configuration.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}
