import Foundation
import SwiftData

/// A connected email account. OAuth tokens are NEVER stored on this model —
/// they live in the Keychain, keyed by `id` (privacy model).
@Model
public final class UserAccount {
    @Attribute(.unique) public var id: UUID
    public var providerRaw: String
    public var emailAddress: String
    public var displayName: String?
    public var connectionStatusRaw: String
    public var grantedScopes: [String]
    public var lastSyncDate: Date?
    /// Provider-specific incremental-sync cursor (Gmail historyId / Graph deltaLink).
    public var syncCursor: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        provider: EmailProviderKind,
        emailAddress: String,
        displayName: String? = nil,
        connectionStatus: ConnectionStatus = .connected,
        grantedScopes: [String] = [],
        lastSyncDate: Date? = nil,
        syncCursor: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerRaw = provider.rawValue
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.connectionStatusRaw = connectionStatus.rawValue
        self.grantedScopes = grantedScopes
        self.lastSyncDate = lastSyncDate
        self.syncCursor = syncCursor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension UserAccount {
    public var provider: EmailProviderKind {
        get { EmailProviderKind(rawValue: providerRaw) ?? .gmail }
        set { providerRaw = newValue.rawValue }
    }

    public var connectionStatus: ConnectionStatus {
        get { ConnectionStatus(rawValue: connectionStatusRaw) ?? .error }
        set { connectionStatusRaw = newValue.rawValue }
    }
}
