import Foundation
import ReceiptImport
import Testing

@Suite("Receipt import primitives")
struct ReceiptImportTests {
    @Test("EML extraction drops headers and decodes quoted printable")
    func eml() {
        let source = "From: Billing <billing@example.com>\r\nSubject: Receipt\r\n\r\nTotal: =2412.99=\r\nMonthly plan"
        let text = EMLTextExtractor.text(from: source)
        #expect(!text.contains("Subject:"))
        #expect(text.contains("$12.99"))
        #expect(text.contains("Monthly plan"))
    }

    @Test("Extracted text is normalized and deterministically hashed")
    func hash() {
        let a = ExtractedDocument(text: "  hello   world ")
        let b = ExtractedDocument(text: "hello world")
        #expect(a.text == "hello world")
        #expect(a.sha256 == b.sha256)
        #expect(a.sha256.count == 64)
    }

    @Test("Secure staging purges only files inside its directory")
    func staging() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try SecureImportStore(directory: directory)
        let url = try store.stage(data: Data("receipt".utf8), preferredExtension: "txt")
        #expect(FileManager.default.fileExists(atPath: url.path))
        try store.purge(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Oversized input is rejected before writing")
    func sizeLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try SecureImportStore(directory: directory)
        #expect(throws: SecureImportError.fileTooLarge) {
            _ = try store.stage(
                data: Data(count: SecureImportStore.maximumBytes + 1),
                preferredExtension: "pdf"
            )
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
