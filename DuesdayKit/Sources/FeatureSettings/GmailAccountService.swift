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
    private let configuration: OAuthConfiguration?
    private static let logger = DuesdayLog.logger(category: "gmail-sync")

    /// Messages fetched per search page.
    private let batchLimit = 25
    /// Backfill pages processed per manual sync tap (≤100 messages).
    private let pagesPerSync = 4

    public init(
        context: ModelContext,
        tokenStore: any TokenStore = KeychainTokenStore(),
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        configuration: OAuthConfiguration? = OAuthConfiguration.googleFromMainBundle()
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

    /// One manual/foreground sync pass. The initial backfill pages through
    /// the targeted search (up to `pagesPerSync` pages per tap, resuming from
    /// the stored page token) so the whole 12-month window is eventually
    /// covered; once the search is exhausted the cursor switches to Gmail
    /// history for incremental updates.
    @discardableResult
    public func sync(account: UserAccount) async throws -> SyncSummary {
        let provider = makeProvider(accountID: account.id)
        let ingestor = CandidateIngestor(context: context)
        var state = SyncCursorState.parse(account.syncCursor)
        var scanned = 0
        var created = 0
        var backfillComplete = true

        do {
            pageLoop: for _ in 0..<pagesPerSync {
                switch state {
                case .backfill(let pageToken):
                    let page = try await provider.searchMessages(
                        ProviderQuery(maxResults: batchLimit, pageToken: pageToken)
                    )
                    let result = try await process(page.refs, provider: provider, ingestor: ingestor, accountID: account.id)
                    scanned += result.scanned
                    created += result.created

                    if let next = page.nextPageToken {
                        state = .backfill(pageToken: next)
                        account.syncCursor = SyncCursorState.encodeBackfill(next)
                        backfillComplete = false
                    } else {
                        // Historical sweep done — arm the incremental cursor.
                        if let historyID = try await provider.currentHistoryID() {
                            account.syncCursor = SyncCursorState.encodeIncremental(historyID)
                        }
                        backfillComplete = true
                        break pageLoop
                    }

                case .incremental(let cursor):
                    switch try await provider.incrementalChanges(since: cursor) {
                    case .changes(let added, let newCursor):
                        let result = try await process(
                            Array(added.prefix(batchLimit * pagesPerSync)),
                            provider: provider,
                            ingestor: ingestor,
                            accountID: account.id
                        )
                        scanned += result.scanned
                        created += result.created
                        account.syncCursor = SyncCursorState.encodeIncremental(newCursor)
                    case .cursorExpired:
                        // Gmail expired the history window — restart backfill.
                        account.syncCursor = SyncCursorState.encodeBackfill(nil)
                        state = .backfill(pageToken: nil)
                        backfillComplete = false
                        continue
                    }
                    break pageLoop
                }
            }
        } catch EmailProviderError.authorizationExpired {
            account.connectionStatus = .expired
            account.updatedAt = .now
            try context.save()
            throw EmailProviderError.authorizationExpired
        }

        account.lastSyncDate = .now
        account.connectionStatus = .connected
        account.updatedAt = .now
        try context.save()
        Self.logger.info("Sync pass: scanned \(scanned, privacy: .public), created \(created, privacy: .public), backfillComplete \(backfillComplete, privacy: .public)")
        return SyncSummary(scanned: scanned, created: created, backfillComplete: backfillComplete)
    }

    private func process(
        _ refs: [MessageRef],
        provider: GmailProvider,
        ingestor: CandidateIngestor,
        accountID: UUID
    ) async throws -> (scanned: Int, created: Int) {
        var created = 0
        for ref in refs {
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
            if case .created = try ingestor.ingest(outcome, sourceAccountID: accountID) {
                created += 1
            }
        }
        return (refs.count, created)
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
    private let configuration: OAuthConfiguration?
    private let httpClient: any HTTPClient
    private let lock = NSLock()

    init(
        accountID: UUID,
        tokenStore: any TokenStore,
        configuration: OAuthConfiguration?,
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
