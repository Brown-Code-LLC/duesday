import CoreModels
import Foundation
import SubscriptionDetection
import SwiftData

@MainActor
public final class ReceiptImportPipeline {
    private let context: ModelContext
    private let store: SecureImportStore

    public init(context: ModelContext, store: SecureImportStore) {
        self.context = context
        self.store = store
    }

    @discardableResult
    public func process(data: Data, filename: String) async throws -> ImportedDocument {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let type = fileType(for: ext)
        let record = ImportedDocument(fileType: type, originalFilename: filename, processingStatus: .processing)
        context.insert(record)
        let staged = try store.stage(data: data, preferredExtension: ext)
        defer { try? store.purge(staged) }

        do {
            let extracted = try await DocumentTextExtractor.extract(data: data, fileExtension: ext)
            let duplicate = try context.fetch(FetchDescriptor<ImportedDocument>()).contains {
                $0.id != record.id && $0.extractedTextHash == extracted.sha256
            }
            if !duplicate {
                let input = EmailMessageInput(
                    messageID: "import-\(record.id.uuidString)",
                    from: filename,
                    subject: filename,
                    date: record.createdAt,
                    plainText: extracted.text,
                    html: nil
                )
                let outcome = DetectionPipeline.analyze(input)
                // Same duplicate ladder as email sync: replayed imports and
                // already-tracked subscriptions don't produce new candidates.
                try CandidateIngestor(context: context).ingest(outcome, sourceAccountID: nil)
            }
            record.extractedTextHash = extracted.sha256
            record.processingStatus = .processed
            record.deletionDate = .now
            try context.save()
            return record
        } catch {
            record.processingStatus = .failed
            record.deletionDate = .now
            try? context.save()
            throw error
        }
    }

    private func fileType(for ext: String) -> ImportFileType {
        switch ext {
        case "pdf": .pdf
        case "png", "jpg", "jpeg", "heic": .image
        case "eml": .emailFile
        default: .text
        }
    }
}
