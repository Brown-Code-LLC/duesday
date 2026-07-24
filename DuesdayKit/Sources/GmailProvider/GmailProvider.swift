import Authentication
import CoreModels
import EmailProviders
import Foundation
import Networking

/// Supplies a currently-valid access token, refreshing (and re-persisting)
/// as needed. Owned by the account service so the provider stays stateless.
public protocol AccessTokenProviding: Sendable {
    func validAccessToken() async throws -> String
    /// Called on a 401 so the owner can force-refresh before one retry.
    func refreshAfterRejection() async throws -> String
}

/// Gmail REST implementation of the provider seam. Targeted searches only —
/// never a mailbox download (docs/05).
public final class GmailProvider: EmailProvider {
    public let kind: EmailProviderKind = .gmail

    private let httpClient: any HTTPClient
    private let tokens: any AccessTokenProviding
    private let baseURL: URL

    public init(
        httpClient: any HTTPClient,
        tokens: any AccessTokenProviding,
        baseURL: URL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    ) {
        self.httpClient = httpClient
        self.tokens = tokens
        self.baseURL = baseURL
    }

    // MARK: - Query building

    /// Builds the Gmail `q` expression: subscription terms OR-ed together,
    /// scoped to the purchases category where available, and time-boxed.
    public static func gmailQuery(for query: ProviderQuery) -> String {
        let orTerms = query.terms
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " OR ")
        return "(\(orTerms)) newer_than:\(query.newerThanDays)d -in:chats -in:spam -in:trash"
    }

    // MARK: - EmailProvider

    public func accountProfile() async throws -> ProviderProfile {
        let payload: GmailProfilePayload = try await get("profile")
        return ProviderProfile(emailAddress: payload.emailAddress)
    }

    public func searchMessages(_ query: ProviderQuery) async throws -> MessagePage {
        var items = [
            URLQueryItem(name: "q", value: Self.gmailQuery(for: query)),
            URLQueryItem(name: "maxResults", value: String(query.maxResults)),
        ]
        if let token = query.pageToken {
            items.append(URLQueryItem(name: "pageToken", value: token))
        }
        let payload: GmailMessageListPayload = try await get("messages", queryItems: items)
        return MessagePage(
            refs: (payload.messages ?? []).map { MessageRef(id: $0.id) },
            nextPageToken: payload.nextPageToken
        )
    }

    public func messageMetadata(_ refs: [MessageRef]) async throws -> [MessageMetadata] {
        var results: [MessageMetadata] = []
        for ref in refs {
            let payload: GmailMessagePayload = try await get(
                "messages/\(ref.id)",
                queryItems: [
                    URLQueryItem(name: "format", value: "metadata"),
                    URLQueryItem(name: "metadataHeaders", value: "From"),
                    URLQueryItem(name: "metadataHeaders", value: "Subject"),
                ]
            )
            results.append(GmailMessageDecoder.metadata(from: payload))
        }
        return results
    }

    public func messageContent(_ ref: MessageRef) async throws -> MessageContent {
        let payload: GmailMessagePayload = try await get(
            "messages/\(ref.id)",
            queryItems: [URLQueryItem(name: "format", value: "full")]
        )
        return GmailMessageDecoder.content(from: payload)
    }

    public func incrementalChanges(since cursor: String?) async throws -> ChangeSet {
        guard let cursor else { return .cursorExpired }
        do {
            var added: [MessageRef] = []
            var newCursor = cursor
            var pageToken: String?
            repeat {
                var items = [
                    URLQueryItem(name: "startHistoryId", value: cursor),
                    URLQueryItem(name: "historyTypes", value: "messageAdded"),
                ]
                if let pageToken {
                    items.append(URLQueryItem(name: "pageToken", value: pageToken))
                }
                let payload: GmailHistoryPayload = try await get("history", queryItems: items)
                for history in payload.history ?? [] {
                    for addition in history.messagesAdded ?? [] {
                        added.append(MessageRef(id: addition.message.id))
                    }
                }
                if let latest = payload.historyId { newCursor = latest }
                pageToken = payload.nextPageToken
            } while pageToken != nil
            return .changes(added: added, newCursor: newCursor)
        } catch EmailProviderError.api(let status) where status == 404 {
            // Gmail expires history cursors; caller falls back to search.
            return .cursorExpired
        }
    }

    public func grantedScopes() async throws -> [String] {
        // Scope introspection needs the tokeninfo endpoint; the token's own
        // scope list (persisted at auth time) is the source of truth locally.
        []
    }

    /// Current profile historyId — the fresh cursor stored after a full sync.
    public func currentHistoryID() async throws -> String? {
        let payload: GmailProfilePayload = try await get("profile")
        return payload.historyId
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw EmailProviderError.decoding }

        var token = try await tokens.validAccessToken()
        var attempt = 0
        while true {
            attempt += 1
            let request = HTTPRequest(url: url, headers: ["Authorization": "Bearer \(token)"])
            do {
                let response = try await httpClient.send(request)
                do {
                    return try response.decoded(T.self)
                } catch {
                    throw EmailProviderError.decoding
                }
            } catch HTTPClientError.status(let status, _) {
                if status == 401, attempt == 1 {
                    // Expired access token: force one refresh, then retry once.
                    token = try await tokens.refreshAfterRejection()
                    continue
                }
                if status == 401 || status == 403 { throw EmailProviderError.authorizationExpired }
                if status == 429 { throw EmailProviderError.rateLimited }
                throw EmailProviderError.api(status: status)
            }
        }
    }
}
