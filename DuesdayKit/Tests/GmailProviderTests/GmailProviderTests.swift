import EmailProviders
import Foundation
import GmailProvider
import Networking
import Testing

private struct ScriptStep: Sendable {
    let check: @Sendable (HTTPRequest) -> Bool
    let result: Result<HTTPResponse, HTTPClientError>

    init(check: @escaping @Sendable (HTTPRequest) -> Bool, result: Result<HTTPResponse, HTTPClientError>) {
        self.check = check
        self.result = result
    }
}

private final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [ScriptStep]
    private var _requests: [HTTPRequest] = []

    var requests: [HTTPRequest] {
        lock.withLock { _requests }
    }

    init(_ script: [ScriptStep]) {
        self.script = script
    }

    private func nextStep(for request: HTTPRequest) -> ScriptStep? {
        lock.withLock {
            _requests.append(request)
            return script.isEmpty ? nil : script.removeFirst()
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let step = nextStep(for: request) else {
            throw HTTPClientError.invalidResponse
        }
        precondition(step.check(request), "unexpected request \(request.url)")
        return try step.result.get()
    }
}

private final class StaticTokens: AccessTokenProviding, @unchecked Sendable {
    var token: String
    var refreshed = false

    init(token: String = "tok-1") {
        self.token = token
    }

    func validAccessToken() async throws -> String { token }
    func refreshAfterRejection() async throws -> String {
        refreshed = true
        token = "tok-2"
        return token
    }
}

private func json(_ text: String, status: Int = 200) -> Result<HTTPResponse, HTTPClientError> {
    .success(HTTPResponse(statusCode: status, data: Data(text.utf8)))
}

@Suite("Gmail query building")
struct GmailQueryTests {
    @Test("Terms are OR-ed, phrases quoted, window and exclusions applied")
    func queryShape() {
        let query = ProviderQuery(terms: ["subscription", "price change"], newerThanDays: 180)
        let q = GmailProvider.gmailQuery(for: query)
        #expect(q.contains("subscription OR \"price change\""))
        #expect(q.contains("newer_than:180d"))
        #expect(q.contains("-in:spam"))
        #expect(q.hasPrefix("("))
    }

    @Test("Default term registry covers the spec's search terms")
    func defaultTerms() {
        let terms = ProviderQuery.defaultTerms
        for expected in ["subscription", "renewal", "trial", "invoice", "auto-renew", "payment failed"] {
            #expect(terms.contains(expected))
        }
    }
}

@Suite("Gmail message decoding")
struct GmailDecodingTests {
    private let messageJSON = """
    {
      "id": "m-1",
      "internalDate": "1753228800000",
      "snippet": "Your receipt",
      "payload": {
        "mimeType": "multipart/alternative",
        "headers": [
          {"name": "From", "value": "Netflix <info@account.netflix.com>"},
          {"name": "Subject", "value": "Your Netflix receipt"}
        ],
        "parts": [
          {"mimeType": "text/plain", "body": {"data": "SGVsbG8gcGxhaW4"}},
          {"mimeType": "text/html", "body": {"data": "PGI-SGVsbG88L2I-"}}
        ]
      }
    }
    """

    @Test("Metadata, plain and HTML parts decode from base64url")
    func decodeFull() async throws {
        let http = ScriptedHTTPClient([
            ScriptStep(check: { $0.url.path.contains("messages/m-1") }, result: json(messageJSON))
        ])
        let provider = GmailProvider(httpClient: http, tokens: StaticTokens())
        let content = try await provider.messageContent(MessageRef(id: "m-1"))
        #expect(content.metadata.from.contains("netflix.com"))
        #expect(content.metadata.subject == "Your Netflix receipt")
        #expect(content.plainText == "Hello plain")
        #expect(content.html == "<b>Hello</b>")
        #expect(content.metadata.date != nil)
    }

    @Test("A 401 triggers one token refresh and a retry")
    func refreshOn401() async throws {
        let tokens = StaticTokens()
        let http = ScriptedHTTPClient([
            ScriptStep(check: { $0.headers["Authorization"] == "Bearer tok-1" },
             result: .failure(HTTPClientError.status(401, Data()))),
            ScriptStep(check: { $0.headers["Authorization"] == "Bearer tok-2" },
             result: json(#"{"emailAddress":"a@b.com"}"#)),
        ])
        let provider = GmailProvider(httpClient: http, tokens: tokens)
        let profile = try await provider.accountProfile()
        #expect(profile.emailAddress == "a@b.com")
        #expect(tokens.refreshed)
    }

    @Test("Persistent 401 surfaces authorizationExpired")
    func expiredAuth() async {
        let http = ScriptedHTTPClient([
            ScriptStep(check: { _ in true }, result: .failure(HTTPClientError.status(401, Data()))),
            ScriptStep(check: { _ in true }, result: .failure(HTTPClientError.status(401, Data()))),
        ])
        let provider = GmailProvider(httpClient: http, tokens: StaticTokens())
        await #expect(throws: EmailProviderError.authorizationExpired) {
            _ = try await provider.accountProfile()
        }
    }
}

@Suite("Gmail incremental sync")
struct GmailHistoryTests {
    @Test("History pages accumulate added messages and advance the cursor")
    func historyPaging() async throws {
        let page1 = """
        {"history":[{"messagesAdded":[{"message":{"id":"m-10"}}]}],
         "historyId":"2000","nextPageToken":"p2"}
        """
        let page2 = """
        {"history":[{"messagesAdded":[{"message":{"id":"m-11"}}]}],
         "historyId":"2001"}
        """
        let http = ScriptedHTTPClient([
            ScriptStep(check: { $0.url.query?.contains("startHistoryId=1000") == true }, result: json(page1)),
            ScriptStep(check: { $0.url.query?.contains("pageToken=p2") == true }, result: json(page2)),
        ])
        let provider = GmailProvider(httpClient: http, tokens: StaticTokens())
        let change = try await provider.incrementalChanges(since: "1000")
        guard case let .changes(added, newCursor) = change else {
            Issue.record("expected changes")
            return
        }
        #expect(added.map(\.id) == ["m-10", "m-11"])
        #expect(newCursor == "2001")
    }

    @Test("An expired history cursor reports cursorExpired for search fallback")
    func expiredCursor() async throws {
        let http = ScriptedHTTPClient([
            ScriptStep(check: { _ in true }, result: .failure(HTTPClientError.status(404, Data())))
        ])
        let provider = GmailProvider(httpClient: http, tokens: StaticTokens())
        let change = try await provider.incrementalChanges(since: "999")
        guard case .cursorExpired = change else {
            Issue.record("expected cursorExpired")
            return
        }
    }

    @Test("A nil cursor is treated as expired (initial backfill via search)")
    func nilCursor() async throws {
        let provider = GmailProvider(httpClient: ScriptedHTTPClient([]), tokens: StaticTokens())
        let change = try await provider.incrementalChanges(since: nil)
        guard case .cursorExpired = change else {
            Issue.record("expected cursorExpired")
            return
        }
    }
}
