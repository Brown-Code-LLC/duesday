import Foundation
import Networking
import Testing

/// Serializes call counting across the @Sendable transport closure.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
        return _count
    }
}

@Suite("HTTP client retry behavior")
struct HTTPClientTests {
    private let url = URL(string: "https://api.example.com/v1/resource")!

    private func response(_ status: Int) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test("Success passes through without retrying")
    func success() async throws {
        let calls = CallCounter()
        let client = URLSessionHTTPClient(
            transport: { _ in
                _ = calls.increment()
                return (Data("ok".utf8), self.response(200))
            },
            sleeper: { _ in },
            jitter: { 0.5 }
        )
        let result = try await client.send(HTTPRequest(url: url))
        #expect(result.statusCode == 200)
        #expect(calls.count == 1)
    }

    @Test("429 and 5xx retry up to the attempt limit, then surface the status")
    func retriesExhausted() async throws {
        let calls = CallCounter()
        let client = URLSessionHTTPClient(
            policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01),
            transport: { _ in
                _ = calls.increment()
                return (Data(), self.response(503))
            },
            sleeper: { _ in },
            jitter: { 0.5 }
        )
        await #expect(throws: HTTPClientError.status(503, Data())) {
            _ = try await client.send(HTTPRequest(url: url))
        }
        #expect(calls.count == 3)
    }

    @Test("Transient failure then success recovers")
    func transientRecovery() async throws {
        let calls = CallCounter()
        let client = URLSessionHTTPClient(
            policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01),
            transport: { _ in
                let n = calls.increment()
                if n < 3 { return (Data(), self.response(500)) }
                return (Data("done".utf8), self.response(200))
            },
            sleeper: { _ in },
            jitter: { 0.5 }
        )
        let result = try await client.send(HTTPRequest(url: url))
        #expect(result.isSuccess)
        #expect(calls.count == 3)
    }

    @Test("Client errors like 404 do not retry")
    func noRetryOnClientError() async throws {
        let calls = CallCounter()
        let client = URLSessionHTTPClient(
            transport: { _ in
                _ = calls.increment()
                return (Data(), self.response(404))
            },
            sleeper: { _ in },
            jitter: { 0.5 }
        )
        await #expect(throws: HTTPClientError.status(404, Data())) {
            _ = try await client.send(HTTPRequest(url: url))
        }
        #expect(calls.count == 1)
    }

    @Test("Timeout URLErrors retry")
    func timeoutRetries() async throws {
        let calls = CallCounter()
        let client = URLSessionHTTPClient(
            policy: RetryPolicy(maxAttempts: 2, baseDelay: 0.01),
            transport: { _ in
                let n = calls.increment()
                if n == 1 { throw URLError(.timedOut) }
                return (Data(), self.response(200))
            },
            sleeper: { _ in },
            jitter: { 0.5 }
        )
        let result = try await client.send(HTTPRequest(url: url))
        #expect(result.isSuccess)
        #expect(calls.count == 2)
    }

    @Test("Backoff delay grows exponentially and respects the cap")
    func backoffCurve() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 4)
        // jitter 1.0 → multiplier 1.0
        #expect(policy.delay(forAttempt: 1, jitter: 1) == 1)
        #expect(policy.delay(forAttempt: 2, jitter: 1) == 2)
        #expect(policy.delay(forAttempt: 3, jitter: 1) == 4)
        #expect(policy.delay(forAttempt: 4, jitter: 1) == 4)
    }

    @Test("Form request encodes fields and content type")
    func formEncoding() {
        let request = HTTPRequest.form(
            url: url,
            fields: ["grant_type": "authorization_code", "code": "abc/+="]
        )
        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(!body.contains(" "))
    }
}
