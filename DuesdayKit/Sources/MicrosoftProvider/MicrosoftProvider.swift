import CoreModels
import EmailProviders
import Foundation
import Networking

public protocol MicrosoftAccessTokenProviding: Sendable {
    func validAccessToken() async throws -> String
    func refreshAfterRejection() async throws -> String
}

/// Microsoft Graph implementation of the provider-neutral email seam.
/// Interactive authentication is intentionally supplied by an MSAL adapter
/// in the app composition layer so this module remains independently tested.
public final class MicrosoftProvider: EmailProvider {
    public let kind: EmailProviderKind = .microsoft

    private let httpClient: any HTTPClient
    private let tokens: any MicrosoftAccessTokenProviding
    private let baseURL: URL
    private let decoder: JSONDecoder

    public init(
        httpClient: any HTTPClient,
        tokens: any MicrosoftAccessTokenProviding,
        baseURL: URL = URL(string: "https://graph.microsoft.com/v1.0/me")!
    ) {
        self.httpClient = httpClient
        self.tokens = tokens
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func accountProfile() async throws -> ProviderProfile {
        let payload: Profile = try await get("")
        return ProviderProfile(
            emailAddress: payload.mail ?? payload.userPrincipalName,
            displayName: payload.displayName
        )
    }

    public func searchMessages(_ query: ProviderQuery) async throws -> MessagePage {
        let search = query.terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        let payload: MessageList = try await get(
            "messages",
            query: [
                URLQueryItem(name: "$search", value: search),
                URLQueryItem(name: "$top", value: String(query.maxResults)),
                URLQueryItem(name: "$select", value: "id"),
                URLQueryItem(name: "$skiptoken", value: query.pageToken),
            ].filter { $0.value != nil }
        )
        return MessagePage(
            refs: payload.value.map { MessageRef(id: $0.id) },
            nextPageToken: Self.queryValue("skiptoken", from: payload.nextLink)
        )
    }

    public func messageMetadata(_ refs: [MessageRef]) async throws -> [MessageMetadata] {
        try await refs.asyncMap { ref in
            let payload: GraphMessage = try await self.get(
                "messages/\(ref.id)",
                query: [URLQueryItem(
                    name: "$select",
                    value: "id,subject,from,receivedDateTime,bodyPreview"
                )]
            )
            return payload.metadata
        }
    }

    public func messageContent(_ ref: MessageRef) async throws -> MessageContent {
        let payload: GraphMessage = try await get(
            "messages/\(ref.id)",
            query: [URLQueryItem(
                name: "$select",
                value: "id,subject,from,receivedDateTime,bodyPreview,body"
            )]
        )
        let html = payload.body?.contentType.lowercased() == "html" ? payload.body?.content : nil
        let plain = html == nil ? payload.body?.content : nil
        return MessageContent(metadata: payload.metadata, plainText: plain, html: html)
    }

    public func incrementalChanges(since cursor: String?) async throws -> ChangeSet {
        guard let cursor, let url = URL(string: cursor) else { return .cursorExpired }
        do {
            let payload: MessageList = try await get(url: url)
            let refs = payload.value.map { MessageRef(id: $0.id) }
            let next = payload.deltaLink ?? payload.nextLink ?? cursor
            return .changes(added: refs, newCursor: next)
        } catch EmailProviderError.api(let status) where status == 404 || status == 410 {
            return .cursorExpired
        }
    }

    public func grantedScopes() async throws -> [String] {
        ["Mail.Read", "offline_access"]
    }

    public func initialDeltaCursor() async throws -> String {
        let payload: MessageList = try await get("mailFolders/inbox/messages/delta")
        return payload.deltaLink ?? payload.nextLink
            ?? baseURL.appendingPathComponent("mailFolders/inbox/messages/delta").absoluteString
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(
            url: path.isEmpty ? baseURL : baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw EmailProviderError.decoding }
        return try await get(url: url)
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        var token = try await tokens.validAccessToken()
        for attempt in 0...1 {
            do {
                let response = try await httpClient.send(HTTPRequest(
                    url: url,
                    headers: ["Authorization": "Bearer \(token)"]
                ))
                return try decoder.decode(T.self, from: response.data)
            } catch HTTPClientError.status(let status, _) {
                if status == 401, attempt == 0 {
                    token = try await tokens.refreshAfterRejection()
                    continue
                }
                if status == 401 || status == 403 { throw EmailProviderError.authorizationExpired }
                if status == 429 { throw EmailProviderError.rateLimited }
                throw EmailProviderError.api(status: status)
            } catch is DecodingError {
                throw EmailProviderError.decoding
            }
        }
        throw EmailProviderError.authorizationExpired
    }

    private static func queryValue(_ name: String, from link: String?) -> String? {
        guard let link, let url = URL(string: link) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name.lowercased().contains(name.lowercased()) }?.value
    }
}

private struct Profile: Decodable {
    let displayName: String?
    let mail: String?
    let userPrincipalName: String
}

private struct MessageList: Decodable {
    let value: [GraphMessage]
    let nextLink: String?
    let deltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }
}

private struct GraphMessage: Decodable {
    struct Sender: Decodable {
        struct Address: Decodable {
            let name: String?
            let address: String
        }
        let emailAddress: Address
    }
    struct Body: Decodable {
        let contentType: String
        let content: String
    }

    let id: String
    let subject: String?
    let from: Sender?
    let receivedDateTime: Date?
    let bodyPreview: String?
    let body: Body?

    var metadata: MessageMetadata {
        let address = from?.emailAddress
        let sender = address.map { "\($0.name ?? $0.address) <\($0.address)>" } ?? ""
        return MessageMetadata(
            id: id,
            from: sender,
            subject: subject ?? "",
            date: receivedDateTime,
            snippet: bodyPreview
        )
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        for element in self { values.append(try await transform(element)) }
        return values
    }
}
