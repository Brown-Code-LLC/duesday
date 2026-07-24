import CoreModels
import Foundation

// Provider-neutral types. Only minimal normalized metadata leaves the
// provider layer — bodies are handed to the detection pipeline and discarded
// (privacy model).

public struct ProviderProfile: Sendable, Equatable {
    public let emailAddress: String
    public let displayName: String?

    public init(emailAddress: String, displayName: String? = nil) {
        self.emailAddress = emailAddress
        self.displayName = displayName
    }
}

public struct MessageRef: Sendable, Hashable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct MessageMetadata: Sendable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: Date?
    public let snippet: String?

    public init(id: String, from: String, subject: String, date: Date?, snippet: String? = nil) {
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
        self.snippet = snippet
    }
}

/// Decoded message content. Held in memory only while the pipeline runs.
public struct MessageContent: Sendable {
    public let metadata: MessageMetadata
    public let plainText: String?
    public let html: String?

    public init(metadata: MessageMetadata, plainText: String?, html: String?) {
        self.metadata = metadata
        self.plainText = plainText
        self.html = html
    }
}

public struct ProviderQuery: Sendable {
    /// Localized subscription-related terms (docs/05: term registry).
    public var terms: [String]
    /// Restrict to messages newer than this many days.
    public var newerThanDays: Int
    public var maxResults: Int
    public var pageToken: String?

    public init(
        terms: [String] = ProviderQuery.defaultTerms,
        newerThanDays: Int = 365,
        maxResults: Int = 50,
        pageToken: String? = nil
    ) {
        self.terms = terms
        self.newerThanDays = newerThanDays
        self.maxResults = maxResults
        self.pageToken = pageToken
    }

    /// English registry for the MVP; per-locale registries land with
    /// localization (roadmap P7). Merchant-specific sender patterns are added
    /// by the provider on top of these.
    public static let defaultTerms: [String] = [
        "subscription", "renewal", "membership", "recurring", "trial",
        "invoice", "receipt", "payment", "charged", "billing", "plan",
        "auto-renew", "cancellation", "price change", "payment failed",
    ]
}

public struct MessagePage: Sendable {
    public let refs: [MessageRef]
    public let nextPageToken: String?

    public init(refs: [MessageRef], nextPageToken: String?) {
        self.refs = refs
        self.nextPageToken = nextPageToken
    }
}

/// Result of an incremental sync attempt.
public enum ChangeSet: Sendable {
    /// New/changed message refs since the cursor, plus the next cursor.
    case changes(added: [MessageRef], newCursor: String)
    /// The provider expired the cursor; caller falls back to windowed search.
    case cursorExpired
}

public enum EmailProviderError: Error, Equatable {
    case notAuthenticated
    case authorizationExpired
    case rateLimited
    case api(status: Int)
    case decoding
}

/// The provider seam (docs/05-integration-strategy.md). GmailProvider ships
/// first; MicrosoftProvider implements the same surface in Phase 6.
public protocol EmailProvider: Sendable {
    var kind: EmailProviderKind { get }

    func accountProfile() async throws -> ProviderProfile
    func searchMessages(_ query: ProviderQuery) async throws -> MessagePage
    func messageMetadata(_ refs: [MessageRef]) async throws -> [MessageMetadata]
    func messageContent(_ ref: MessageRef) async throws -> MessageContent
    func incrementalChanges(since cursor: String?) async throws -> ChangeSet
    func grantedScopes() async throws -> [String]
}
