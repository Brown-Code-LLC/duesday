import Foundation

/// Minimal HTTP abstraction so every network integration is mockable.
public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: Method = .get,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// Convenience for `application/x-www-form-urlencoded` POST bodies
    /// (OAuth token endpoints).
    public static func form(url: URL, fields: [String: String]) -> HTTPRequest {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((components.percentEncodedQuery ?? "").utf8)
        return HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public func decoded<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: data)
    }
}

public enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case transport(code: Int)
    /// Non-2xx after retries were exhausted (or non-retryable).
    case status(Int, Data)

    public static func == (lhs: HTTPClientError, rhs: HTTPClientError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): true
        case let (.transport(a), .transport(b)): a == b
        case let (.status(a, _), .status(b, _)): a == b
        default: false
        }
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
