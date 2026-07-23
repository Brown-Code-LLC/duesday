import Foundation
import SwiftData

/// Record of a user-imported file (receipt, screenshot, PDF, .eml, text).
/// The file itself lives in the protected imports directory and is purged
/// after processing; only this metadata and a content hash remain.
@Model
public final class ImportedDocument {
    @Attribute(.unique) public var id: UUID
    public var fileTypeRaw: String
    public var originalFilename: String
    public var processingStatusRaw: String
    /// SHA-256 of the normalized extracted text — deduplicates re-imports
    /// without retaining the content itself (privacy model).
    public var extractedTextHash: String?
    public var createdAt: Date
    /// When the underlying file was (or is scheduled to be) deleted.
    public var deletionDate: Date?

    public init(
        id: UUID = UUID(),
        fileType: ImportFileType,
        originalFilename: String,
        processingStatus: ProcessingStatus = .pending,
        extractedTextHash: String? = nil,
        createdAt: Date = .now,
        deletionDate: Date? = nil
    ) {
        self.id = id
        self.fileTypeRaw = fileType.rawValue
        self.originalFilename = originalFilename
        self.processingStatusRaw = processingStatus.rawValue
        self.extractedTextHash = extractedTextHash
        self.createdAt = createdAt
        self.deletionDate = deletionDate
    }
}

extension ImportedDocument {
    public var fileType: ImportFileType {
        get { ImportFileType(rawValue: fileTypeRaw) ?? .text }
        set { fileTypeRaw = newValue.rawValue }
    }

    public var processingStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: processingStatusRaw) ?? .pending }
        set { processingStatusRaw = newValue.rawValue }
    }
}
