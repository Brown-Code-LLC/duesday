import Authentication
import CoreModels
import EmailProviders
import Foundation
import MicrosoftProvider
import Networking
import SubscriptionDetection
import SwiftData
import os

/// Microsoft (Outlook) account lifecycle, mirroring the Gmail service over
/// the Graph provider: connect via PKCE (public client, no MSAL dependency),
/// delta-query incremental sync with search fallback, disconnect with local
/// wipe (Microsoft identity has no revocation endpoint; access is removed
/// from the user's Microsoft account portal).
@MainActor
public final class MicrosoftAccountService {
    public enum ServiceError: LocalizedError {
        case notConfigured

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Outlook isn't configured in this build yet. A Microsoft Entra client ID must be added before accounts can be connected."
            }
        }
    }

    private let context: ModelContext
    private let tokenStore: any TokenStore
    private let httpClient: any HTTPClient
    private let configuration: OAuthConfiguration?
    private static let logger = DuesdayLog.logger(category: "microsoft-sync")
    /// Messages fetched per search page.
    private let batchLimit = 25
    /// Backfill pages processed per manual sync tap (≤100 messages).
    private let pagesPerSync = 4

    public init(
        context: ModelContext,
        tokenStore: any TokenStore = KeychainTokenStore(),
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        configuration: OAuthConfiguration? = OAuthConfiguration.microsoftFromMainBundle()
    ) {
        self.context = context
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.configuration = configuration
    }

    public var isConfigured: Bool { configuration != nil }

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
            provider: .microsoft,
            emailAddress: "",
            connectionStatus: .connected,
            grantedScopes: token.scopes
        )
        try tokenStore.save(token, accountID: account.id)

        let provider = makeProvider(accountID: account.id)
        let profile = try await provider.accountProfile()
        account.emailAddress = profile.emailAddress
        account.displayName = profile.displayName
        account.updatedAt = .now
        context.insert(account)
        try context.save()
        return account
    }

    /// Backfill pages through the Graph search (resuming from the stored
    /// skip token) until exhausted, then switches to delta-query incremental
    /// sync — mirroring the Gmail service.
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
                        let delta = try await provider.initialDeltaCursor()
                        account.syncCursor = SyncCursorState.encodeIncremental(delta)
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
        provider: MicrosoftProvider,
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
            let outcome = DetectionPipeline.analyze(input)
            if case .created = try ingestor.ingest(outcome, sourceAccountID: accountID) {
                created += 1
            }
        }
        return (refs.count, created)
    }

    public func disconnect(account: UserAccount, purgeImportedData: Bool) async throws {
        try? tokenStore.delete(accountID: account.id)
        if purgeImportedData {
            let accountID = account.id
            let descriptor = FetchDescriptor<DetectionCandidate>(
                predicate: #Predicate { $0.sourceAccountID == accountID }
            )
            for candidate in try context.fetch(descriptor) {
                context.delete(candidate)
            }
        }
        context.delete(account)
        try context.save()
    }

    private func makeProvider(accountID: UUID) -> MicrosoftProvider {
        MicrosoftProvider(
            httpClient: httpClient,
            tokens: MicrosoftTokenRefresher(
                accountID: accountID,
                tokenStore: tokenStore,
                configuration: configuration,
                httpClient: httpClient
            )
        )
    }
}

private final class MicrosoftTokenRefresher: MicrosoftAccessTokenProviding, @unchecked Sendable {
    private let accountID: UUID
    private let tokenStore: any TokenStore
    private let configuration: OAuthConfiguration?
    private let httpClient: any HTTPClient

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
