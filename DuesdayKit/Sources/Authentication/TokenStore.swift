import CoreModels
import Foundation
import Security
import os

/// OAuth token material for one connected account. Never persisted outside
/// the token store (privacy model, hard rule 1).
public struct OAuthToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiryDate: Date
    public var scopes: [String]

    public init(accessToken: String, refreshToken: String?, expiryDate: Date, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiryDate = expiryDate
        self.scopes = scopes
    }

    public func isExpired(now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiryDate
    }
}

public enum TokenStoreError: Error, Equatable {
    case keychain(OSStatus)
    case corruptData
}

/// Seam over token persistence, keyed by the local `UserAccount.id`.
public protocol TokenStore: Sendable {
    func save(_ token: OAuthToken, accountID: UUID) throws
    func load(accountID: UUID) throws -> OAuthToken?
    func delete(accountID: UUID) throws
}

/// Keychain-backed store: `AfterFirstUnlockThisDeviceOnly`, never synced to
/// iCloud, so tokens don't travel in backups (privacy model).
public final class KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String = "app.duesday.oauth") {
        self.service = service
    }

    private func baseQuery(accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }

    public func save(_ token: OAuthToken, accountID: UUID) throws {
        let data = try JSONEncoder().encode(token)
        var query = baseQuery(accountID: accountID)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status) }
    }

    public func load(accountID: UUID) throws -> OAuthToken? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = try? JSONDecoder().decode(OAuthToken.self, from: data)
            else { throw TokenStoreError.corruptData }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychain(status)
        }
    }

    public func delete(accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status)
        }
    }
}

/// Test/preview double.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: OAuthToken] = [:]

    public init() {}

    public func save(_ token: OAuthToken, accountID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[accountID] = token
    }

    public func load(accountID: UUID) throws -> OAuthToken? {
        lock.lock(); defer { lock.unlock() }
        return storage[accountID]
    }

    public func delete(accountID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[accountID] = nil
    }
}
