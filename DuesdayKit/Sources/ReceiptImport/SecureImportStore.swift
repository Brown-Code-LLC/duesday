import Foundation

public enum SecureImportError: Error, Equatable {
    case fileTooLarge
    case unsupportedType
    case unreadable
}

/// Short-lived protected storage for user-selected source documents.
public struct SecureImportStore: Sendable {
    public static let maximumBytes = 20 * 1_024 * 1_024
    public let directory: URL

    public init(directory: URL? = nil) throws {
        let root = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        self.directory = root
    }

    public func stage(data: Data, preferredExtension: String) throws -> URL {
        guard data.count <= Self.maximumBytes else { throw SecureImportError.fileTooLarge }
        let safeExtension = preferredExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(safeExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    public func purge(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == directory.standardizedFileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        if FileManager.default.fileExists(atPath: standardized.path) {
            try FileManager.default.removeItem(at: standardized)
        }
    }

    public func purgeExpired(olderThan cutoff: Date) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls {
            let created = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            if created < cutoff { try purge(url) }
        }
    }
}
