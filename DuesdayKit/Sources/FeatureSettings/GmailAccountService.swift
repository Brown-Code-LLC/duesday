import Authentication
import CoreModels
import EmailProviders
import Foundation
import GmailProvider
import Networking
import SubscriptionDetection
import SwiftData
import os

/// Orchestrates the Gmail account lifecycle: connect (OAuth → profile →
/// account record + Keychain token), sync (incremental with search fallback →
/// detection pipeline → review queue), and disconnect (revoke + wipe).
@MainActor
public final class GmailAccountService {
    public enum ServiceError: LocalizedError {
        case notConfigured
        case accountMissing

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Gmail isn't configured in this build yet. A Google OAuth client ID must be added before accounts can be connected."
            case .accountMissing:
                "This account is no longer available."
            }
        }
    }

    private let context: ModelContext
    private let tokenStore: any TokenStore
    private let httpClient: any HTTPClient
    private let configuration: GoogleOAuthConfiguration?
    private static let logger = DuesdayLog.logger(category: "gmail-sync")

    /// How many messages are fetched and analyzed per manual sync pass.
    private let batchLimit = 25

    public init(
        context: ModelContext,
        tokenStore: any TokenStore = KeychainTokenStore(),
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        configuration: GoogleOAuthConfiguration? = GoogleOAuthConfiguration.fromMainBundle()
    ) {
        self.context = context
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.configuration = configuration
    }

    public var isConfigured: Bool { configuration != nil }

    // MARK: - Connect

    @discardableResult
    public func connect() async throws -> UserAccount {
        guard let configuration else { throw ServiceError.notConfigured }
        let oauth = OAuthService(
            configuration: configuration,
            httpClient: httpClient,
            authorizationUI: WebAuthenticationUI()
        )
        let token = try await oauth.signIn()

        let account = UserAccount(
            provider: .gmail,
            emailAddress: "",
            connectionStatus: .connected,
            grantedScopes: token.scopes
        )
        try tokenStore.save(token, accountID: account.id)

        let provider = makeProvider(accountID: account.id)
        let profile = try await provider.accountProfile()
        account.emailAddress = profile.emailAddress
        account.updatedAt = .now
        context.insert(account)
        try context.save()
        return account
    }

    // MARK: - Sync

    /// One manual/foreground sync pass. Incremental when a cursor exists,
    /// falling back to the targeted backfill search.
    @discardableResult
    public func sync(account: UserAccount) async throws -> Int {
        let provider = makeProvider(accountID: account.id)
        var refs: [MessageRef] = []
        var newCursor: String?

        do {
            switch try await provider.incrementalChanges(since: account.syncCursor) {
            case .changes(let added, let cursor):
                refs = added
                newCursor = cursor
            case .cursorExpired:
                let page = try await provider.searchMessages(ProviderQuery(maxResults: batchLimit))
                refs = page.refs
                newCursor = try await provider.currentHistoryID()
            }
        } catch EmailProviderError.authorizationExpired {
            account.connectionStatus = .expired
            account.updatedAt = .now
            try context.save()
            throw EmailProviderError.authorizationExpired
        }

        let ingestor = CandidateIngestor(context: context)
        var created = 0
        for ref in refs.prefix(batchLimit) {
            let content = try await provider.messageContent(ref)
            let input = EmailMessageInput(
                messageID: content.metadata.id,
                from: content.metadata.from,
                subject: content.metadata.subject,
                date: content.metadata.date,
                plainText: content.plainText,
                html: content.html
            )
            // Pure, synchronous analysis; content is discarded right after.
            let outcome = DetectionPipeline.analyze(input)
            if case .created = try ingestor.ingest(outcome, sourceAccountID: account.id) {
                created += 1
            }
        }

        account.lastSyncDate = .now
        if let newCursor { account.syncCursor = newCursor }
        account.connectionStatus = .connected
        account.updatedAt = .now
        try context.save()
        Self.logger.info("Sync finished: \(created, privacy: .public) new candidates from \(refs.count, privacy: .public) messages")
        return created
    }

    // MARK: - Disconnect & data deletion

    /// Revokes access, deletes the Keychain token, removes the account, and
    /// optionally purges everything imported from it (privacy model).
    public func disconnect(account: UserAccount, purgeImportedData: Bool) async throws {
        if let configuration, let token = try? tokenStore.load(accountID: account.id) {
            let oauth = OAuthService(
                configuration: configuration,
                httpClient: httpClient,
                authorizationUI: WebAuthenticationUI()
            )
            await oauth.revoke(token: token)
        }
        try? tokenStore.delete(accountID: account.id)

        if purgeImportedData {
            try purgeCandidates(accountID: account.id)
        }
        context.delete(account)
        try context.save()
    }

    /// Deletes all detections imported from this account, including resolved
    /// ones (delete-imported-data flow).
    public func purgeCandidates(accountID: UUID) throws {
        let descriptor = FetchDescriptor<DetectionCandidate>(
            predicate: #Predicate { $0.sourceAccountID == accountID }
        )
        for candidate in try context.fetch(descriptor) {
            context.delete(candidate)
        }
        try context.save()
    }

    // MARK: - Provider assembly

    private func makeProvider(accountID: UUID) -> GmailProvider {
        GmailProvider(
            httpClient: httpClient,
            tokens: TokenRefresher(
                accountID: accountID,
                tokenStore: tokenStore,
                configuration: configuration,
                httpClient: httpClient
            )
        )
    }
}

/// Bridges the provider's token needs to the Keychain store, refreshing
/// through OAuth when the access token is stale or rejected.
private final class TokenRefresher: AccessTokenProviding, @unchecked Sendable {
    private let accountID: UUID
    private let tokenStore: any TokenStore
    private let configuration: GoogleOAuthConfiguration?
    private let httpClient: any HTTPClient
    private let lock = NSLock()

    init(
        accountID: UUID,
        tokenStore: any TokenStore,
        configuration: GoogleOAuthConfiguration?,
        httpClient: any HTTPClient
    ) {
        self.accountID = accountID
        self.tokenStore = tokenStore
        self.configuration = configuration
        self.httpClient = httpClient
    }

    func validAccessToken() async throws -> String {
        guard let token = try tokenStore.load(accountID: accountID) else {
            throw EmailProviderError.notAuthenticated
        }
        if !token.isExpired() {
            return token.accessToken
        }
        return try await refresh(token).accessToken
    }

    func refreshAfterRejection() async throws -> String {
        guard let token = try tokenStore.load(accountID: accountID) else {
            throw EmailProviderError.notAuthenticated
        }
        return try await refresh(token).accessToken
    }

    private func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard let configuration else { throw EmailProviderError.notAuthenticated }
        let oauth = OAuthService(
            configuration: configuration,
            httpClient: httpClient,
            authorizationUI: WebAuthenticationUI()
        )
        do {
            let refreshed = try await oauth.refresh(token: token)
            try tokenStore.save(refreshed, accountID: accountID)
            return refreshed
        } catch {
            throw EmailProviderError.authorizationExpired
        }
    }
}
