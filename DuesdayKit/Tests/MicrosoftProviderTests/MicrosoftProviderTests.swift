import EmailProviders
import Foundation
import MicrosoftProvider
import Networking
import Testing

private struct Tokens: MicrosoftAccessTokenProviding {
    func validAccessToken() async throws -> String { "access" }
    func refreshAfterRejection() async throws -> String { "refreshed" }
}

private final class HTTPMock: HTTPClient, @unchecked Sendable {
    let response: HTTPResponse
    init(_ json: String) {
        response = HTTPResponse(statusCode: 200, data: Data(json.utf8))
    }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { response }
}

@Suite("Microsoft Graph provider")
struct MicrosoftProviderTests {
    @Test("Profile normalizes the Graph account")
    func profile() async throws {
        let provider = MicrosoftProvider(
            httpClient: HTTPMock(#"{"displayName":"N","mail":"n@example.com","userPrincipalName":"n@example.com"}"#),
            tokens: Tokens(),
            baseURL: URL(string: "https://example.test/me")!
        )
        let profile = try await provider.accountProfile()
        #expect(profile.emailAddress == "n@example.com")
        #expect(profile.displayName == "N")
    }

    @Test("Initial sync without a delta cursor requests search fallback")
    func initialDelta() async throws {
        let provider = MicrosoftProvider(
            httpClient: HTTPMock(#"{"value":[]}"#),
            tokens: Tokens()
        )
        guard case .cursorExpired = try await provider.incrementalChanges(since: nil) else {
            Issue.record("Expected expired cursor")
            return
        }
    }
}
