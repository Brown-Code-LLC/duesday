import Authentication
import Foundation
import Networking
import Testing

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private var _requests: [HTTPRequest] = []

    var requests: [HTTPRequest] {
        lock.withLock { _requests }
    }

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    private func nextResponse(for request: HTTPRequest) -> HTTPResponse? {
        lock.withLock {
            _requests.append(request)
            return responses.isEmpty ? nil : responses.removeFirst()
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let response = nextResponse(for: request) else {
            throw HTTPClientError.invalidResponse
        }
        return response
    }
}

private struct MockAuthorizationUI: AuthorizationUI {
    let callback: @Sendable (URL) -> URL

    @MainActor
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        callback(url)
    }
}

@Suite("PKCE")
struct PKCETests {
    @Test("Challenge is the base64url SHA-256 of the verifier (RFC 7636 vector)")
    func rfcTestVector() {
        // RFC 7636 appendix B: this octet sequence produces the known
        // verifier/challenge pair.
        let octets: [UInt8] = [
            116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173,
            187, 186, 22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83,
            132, 141, 121,
        ]
        let pkce = PKCE(verifierBytes: octets)
        #expect(pkce.codeVerifier == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Verifiers are unique and URL-safe")
    func uniqueness() {
        let a = PKCE()
        let b = PKCE()
        #expect(a.codeVerifier != b.codeVerifier)
        #expect(!a.codeVerifier.contains("+"))
        #expect(!a.codeVerifier.contains("/"))
        #expect(!a.codeVerifier.contains("="))
    }

    @Test("Base64url round-trips including padding cases")
    func base64URL() {
        for length in 1...5 {
            let data = Data((0..<length).map(UInt8.init))
            let encoded = data.base64URLEncodedString()
            #expect(Data(base64URLEncoded: encoded) == data)
        }
    }
}

@Suite("Token store")
struct TokenStoreTests {
    private var sample: OAuthToken {
        OAuthToken(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiryDate: Date(timeIntervalSince1970: 2_000_000_000),
            scopes: ["gmail.readonly"]
        )
    }

    @Test("In-memory store round-trips and deletes")
    func inMemory() throws {
        let store = InMemoryTokenStore()
        let id = UUID()
        try store.save(sample, accountID: id)
        #expect(try store.load(accountID: id) == sample)
        try store.delete(accountID: id)
        #expect(try store.load(accountID: id) == nil)
    }

    @Test("Keychain store round-trips where the environment permits")
    func keychain() throws {
        let store = KeychainTokenStore(service: "app.duesday.oauth.tests")
        let id = UUID()
        do {
            try store.save(sample, accountID: id)
        } catch TokenStoreError.keychain {
            // Headless CI keychains can refuse writes; the store's behavior is
            // covered on-device. Nothing further to assert here.
            return
        }
        #expect(try store.load(accountID: id) == sample)
        try store.delete(accountID: id)
        #expect(try store.load(accountID: id) == nil)
    }

    @Test("Expiry respects leeway")
    func expiry() {
        let token = OAuthToken(
            accessToken: "a", refreshToken: nil,
            expiryDate: Date(timeIntervalSince1970: 1_000),
            scopes: []
        )
        #expect(token.isExpired(now: Date(timeIntervalSince1970: 990), leeway: 60))
        #expect(!token.isExpired(now: Date(timeIntervalSince1970: 900), leeway: 60))
    }
}

@Suite("OAuth service")
struct OAuthServiceTests {
    private var configuration: GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(clientID: "12345-abc.apps.googleusercontent.com")
    }

    @Test("Redirect scheme is the reversed client ID")
    func redirectScheme() {
        #expect(configuration.redirectScheme == "com.googleusercontent.apps.12345-abc")
    }

    @Test("Authorization URL carries PKCE, scope, and offline access")
    func authorizationURL() {
        let service = OAuthService(
            configuration: configuration,
            httpClient: MockHTTPClient(responses: []),
            authorizationUI: MockAuthorizationUI(callback: { $0 })
        )
        let pkce = PKCE(verifierBytes: Array(repeating: 7, count: 32))
        let url = service.authorizationURL(pkce: pkce, state: "state-1")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        #expect(value("code_challenge") == pkce.codeChallenge)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("scope")?.contains("gmail.readonly") == true)
        #expect(value("access_type") == "offline")
        #expect(value("state") == "state-1")
    }

    @Test("Sign-in exchanges the code and keeps the refresh token")
    @MainActor
    func signInFlow() async throws {
        let tokenJSON = Data("""
        {"access_token":"at-1","refresh_token":"rt-1","expires_in":3600,"scope":"a b"}
        """.utf8)
        let http = MockHTTPClient(responses: [HTTPResponse(statusCode: 200, data: tokenJSON)])
        let ui = MockAuthorizationUI { authURL in
            // Echo back a valid callback preserving the state parameter.
            let state = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "scheme:/oauth2redirect?code=code-1&state=\(state)")!
        }
        let service = OAuthService(configuration: configuration, httpClient: http, authorizationUI: ui)

        let token = try await service.signIn()
        #expect(token.accessToken == "at-1")
        #expect(token.refreshToken == "rt-1")
        #expect(token.scopes == ["a", "b"])

        let body = String(decoding: http.requests[0].body ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier="))
        #expect(!body.contains("client_secret"))
    }

    @Test("A tampered state parameter is rejected")
    @MainActor
    func stateMismatch() async {
        let ui = MockAuthorizationUI { _ in
            URL(string: "scheme:/oauth2redirect?code=code-1&state=WRONG")!
        }
        let service = OAuthService(
            configuration: configuration,
            httpClient: MockHTTPClient(responses: []),
            authorizationUI: ui
        )
        await #expect(throws: OAuthError.invalidCallback) {
            _ = try await service.signIn()
        }
    }

    @Test("Refresh keeps the original refresh token when the server omits it")
    func refreshKeepsToken() async throws {
        let tokenJSON = Data("""
        {"access_token":"at-2","expires_in":3600}
        """.utf8)
        let http = MockHTTPClient(responses: [HTTPResponse(statusCode: 200, data: tokenJSON)])
        let service = OAuthService(
            configuration: configuration,
            httpClient: http,
            authorizationUI: MockAuthorizationUI(callback: { $0 })
        )
        let original = OAuthToken(accessToken: "old", refreshToken: "rt-keep", expiryDate: .now, scopes: [])
        let refreshed = try await service.refresh(token: original)
        #expect(refreshed.accessToken == "at-2")
        #expect(refreshed.refreshToken == "rt-keep")
    }

    @Test("Refresh without a refresh token fails cleanly")
    func refreshWithoutToken() async {
        let service = OAuthService(
            configuration: configuration,
            httpClient: MockHTTPClient(responses: []),
            authorizationUI: MockAuthorizationUI(callback: { $0 })
        )
        let token = OAuthToken(accessToken: "a", refreshToken: nil, expiryDate: .now, scopes: [])
        await #expect(throws: OAuthError.noRefreshToken) {
            _ = try await service.refresh(token: token)
        }
    }
}
