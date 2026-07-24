import CoreModels
import Foundation
import os

/// Retry policy: exponential backoff with jitter for transient failures
/// (429, 5xx, timeouts). Sleep is injectable so tests run instantly.
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int, jitter: Double) -> TimeInterval {
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        return min(maxDelay, exponential) * (0.5 + jitter / 2)
    }

    public static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || (500..<600).contains(statusCode)
    }
}

public final class URLSessionHTTPClient: HTTPClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let transport: Transport
    private let policy: RetryPolicy
    private let sleeper: Sleeper
    private let jitter: @Sendable () -> Double
    private static let logger = DuesdayLog.logger(category: "networking")

    public init(
        session: URLSession = .shared,
        policy: RetryPolicy = RetryPolicy(),
        transport: Transport? = nil,
        sleeper: Sleeper? = nil,
        jitter: (@Sendable () -> Double)? = nil
    ) {
        self.transport = transport ?? { request in try await session.data(for: request) }
        self.policy = policy
        self.sleeper = sleeper ?? { try await Task.sleep(for: .seconds($0)) }
        self.jitter = jitter ?? { Double.random(in: 0...1) }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        var lastError: Error = HTTPClientError.invalidResponse
        for attempt in 1...policy.maxAttempts {
            do {
                let (data, response) = try await transport(urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw HTTPClientError.invalidResponse
                }
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let key = key as? String, let value = value as? String {
                        headers[key] = value
                    }
                }
                let result = HTTPResponse(statusCode: http.statusCode, headers: headers, data: data)
                if result.isSuccess { return result }
                if RetryPolicy.isRetryable(statusCode: http.statusCode), attempt < policy.maxAttempts {
                    lastError = HTTPClientError.status(http.statusCode, data)
                    Self.logger.info("Retrying after HTTP \(http.statusCode, privacy: .public) (attempt \(attempt, privacy: .public))")
                    try await sleeper(policy.delay(forAttempt: attempt, jitter: jitter()))
                    continue
                }
                throw HTTPClientError.status(http.statusCode, data)
            } catch let error as HTTPClientError {
                throw error
            } catch let error as URLError where isRetryable(error) && attempt < policy.maxAttempts {
                lastError = error
                Self.logger.info("Retrying after URLError \(error.code.rawValue, privacy: .public) (attempt \(attempt, privacy: .public))")
                try await sleeper(policy.delay(forAttempt: attempt, jitter: jitter()))
            }
        }
        throw lastError
    }

    private func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }
}
