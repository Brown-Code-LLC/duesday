import CoreModels
import Foundation
import Networking

#if os(iOS)
import AuthenticationServices
import UIKit
#endif

/// Provider-agnostic OAuth configuration for the installed-app (PKCE,
/// no-secret) flow. Client IDs are developer-supplied — see
/// docs/05-integration-strategy.md.
public struct OAuthConfiguration: Sendable {
    public let clientID: String
    public let scopes: [String]
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    /// Some providers (Microsoft identity) have no revocation endpoint;
    /// local token deletion still happens on disconnect.
    public let revocationEndpoint: URL?
    public let redirectScheme: String
    public let redirectURI: String
    /// Provider-specific authorization parameters (e.g. Google's
    /// `access_type=offline`).
    public let extraAuthorizationParameters: [String: String]

    public init(
        clientID: String,
        scopes: [String],
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        revocationEndpoint: URL?,
        redirectScheme: String,
        redirectURI: String,
        extraAuthorizationParameters: [String: String] = [:]
    ) {
        self.clientID = clientID
        self.scopes = scopes
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.redirectScheme = redirectScheme
        self.redirectURI = redirectURI
        self.extraAuthorizationParameters = extraAuthorizationParameters
    }

    /// Google installed-app client. iOS Google clients use the reversed
    /// client ID as the redirect scheme; offline access is requested
    /// explicitly so a refresh token is issued.
    public static func google(clientID: String) -> OAuthConfiguration {
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        return OAuthConfiguration(
            clientID: clientID,
            scopes: ["https://www.googleapis.com/auth/gmail.readonly"],
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            revocationEndpoint: URL(string: "https://oauth2.googleapis.com/revoke")!,
            redirectScheme: scheme,
            redirectURI: "\(scheme):/oauth2redirect",
            extraAuthorizationParameters: ["access_type": "offline", "prompt": "consent"]
        )
    }

    /// Microsoft identity platform public client (PKCE — no secret, no MSAL
    /// dependency; ADR-6 amendment). Refresh tokens come from the
    /// `offline_access` scope. The redirect URI must be registered on the
    /// Entra app as a mobile/desktop platform redirect.
    public static func microsoft(clientID: String) -> OAuthConfiguration {
        OAuthConfiguration(
            clientID: clientID,
            scopes: [
                "https://graph.microsoft.com/Mail.Read",
                "offline_access", "openid", "email",
            ],
            authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            revocationEndpoint: nil,
            redirectScheme: "duesday.oauth",
            redirectURI: "duesday.oauth://microsoft"
        )
    }

    /// Reads the Google client ID from Info.plist. [PLACEHOLDER: developer
    /// credential — set `DuesdayGoogleOAuthClientID` to the iOS OAuth client
    /// ID from Google Cloud Console.]
    public static func googleFromMainBundle() -> OAuthConfiguration? {
        guard let clientID = mainBundleValue("DuesdayGoogleOAuthClientID"),
              clientID != "YOUR_CLIENT_ID.apps.googleusercontent.com"
        else { return nil }
        return .google(clientID: clientID)
    }

    /// Reads the Microsoft client ID from Info.plist. [PLACEHOLDER: developer
    /// credential — set `DuesdayMicrosoftOAuthClientID` to the Entra app
    /// registration's application (client) ID.]
    public static func microsoftFromMainBundle() -> OAuthConfiguration? {
        guard let clientID = mainBundleValue("DuesdayMicrosoftOAuthClientID") else { return nil }
        return .microsoft(clientID: clientID)
    }

    private static func mainBundleValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}

/// Backwards-compatible name used by earlier call sites.
public typealias GoogleOAuthConfiguration = OAuthConfiguration

public enum OAuthError: Error, Equatable {
    case notConfigured
    case userCancelled
    case invalidCallback
    case exchangeFailed(Int)
    case refreshFailed(Int)
    case noRefreshToken
    case webAuthUnavailable
}

/// Seam over the system web-auth UI so the flow is testable.
public protocol AuthorizationUI: Sendable {
    @MainActor func authorize(url: URL, callbackScheme: String) async throws -> URL
}

/// Runs the full authorization-code + PKCE flow and token lifecycle.
public final class OAuthService: Sendable {
    private let configuration: OAuthConfiguration
    private let httpClient: any HTTPClient
    private let authorizationUI: any AuthorizationUI
    private static let logger = DuesdayLog.logger(category: "auth")

    public init(
        configuration: OAuthConfiguration,
        httpClient: any HTTPClient,
        authorizationUI: any AuthorizationUI
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.authorizationUI = authorizationUI
    }

    // MARK: - Authorization

    public func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.challengeMethod),
            URLQueryItem(name: "state", value: state),
        ]
        for (name, value) in configuration.extraAuthorizationParameters.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        return components.url!
    }

    /// Full interactive sign-in: browser session → code → token exchange.
    @MainActor
    public func signIn() async throws -> OAuthToken {
        let pkce = PKCE()
        let state = UUID().uuidString
        let url = authorizationURL(pkce: pkce, state: state)
        let callback = try await authorizationUI.authorize(url: url, callbackScheme: configuration.redirectScheme)

        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw OAuthError.invalidCallback }

        return try await exchange(code: code, pkce: pkce)
    }

    public func exchange(code: String, pkce: PKCE) async throws -> OAuthToken {
        let request = HTTPRequest.form(url: configuration.tokenEndpoint, fields: [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": pkce.codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI,
        ])
        let response = try await httpClient.send(request)
        guard response.isSuccess else { throw OAuthError.exchangeFailed(response.statusCode) }
        return try Self.token(from: response, fallbackRefreshToken: nil)
    }

    public func refresh(token: OAuthToken) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.noRefreshToken }
        let request = HTTPRequest.form(url: configuration.tokenEndpoint, fields: [
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        let response = try await httpClient.send(request)
        guard response.isSuccess else { throw OAuthError.refreshFailed(response.statusCode) }
        return try Self.token(from: response, fallbackRefreshToken: refreshToken)
    }

    /// Best-effort server-side revocation; local deletion happens regardless.
    /// Providers without a revocation endpoint (Microsoft identity) rely on
    /// the account portal, so this becomes a no-op there.
    public func revoke(token: OAuthToken) async {
        guard let endpoint = configuration.revocationEndpoint else { return }
        let credential = token.refreshToken ?? token.accessToken
        let request = HTTPRequest.form(url: endpoint, fields: ["token": credential])
        _ = try? await httpClient.send(request)
    }

    // MARK: - Decoding

    private struct TokenPayload: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let scope: String?
    }

    private static func token(from response: HTTPResponse, fallbackRefreshToken: String?) throws -> OAuthToken {
        let payload = try response.decoded(TokenPayload.self)
        return OAuthToken(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token ?? fallbackRefreshToken,
            expiryDate: Date.now.addingTimeInterval(payload.expires_in),
            scopes: payload.scope?.split(separator: " ").map(String.init) ?? []
        )
    }
}

// MARK: - System web auth

#if os(iOS)
/// ASWebAuthenticationSession-backed authorization UI.
public final class WebAuthenticationUI: NSObject, AuthorizationUI {
    public override init() {
        super.init()
    }

    @MainActor
    public func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let presenter = PresentationAnchorProvider()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.userCancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: OAuthError.webAuthUnavailable)
            }
        }
    }
}

private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
#else
/// macOS test builds have no web-auth UI; the flow is exercised via mocks.
public final class WebAuthenticationUI: AuthorizationUI {
    public init() {}

    @MainActor
    public func authorize(url: URL, callbackScheme: String) async throws -> URL {
        throw OAuthError.webAuthUnavailable
    }
}
#endif
