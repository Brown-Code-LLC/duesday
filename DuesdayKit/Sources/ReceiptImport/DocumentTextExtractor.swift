import CryptoKit
import Foundation
import SubscriptionDetection

#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif

public struct ExtractedDocument: Sendable {
    public let text: String
    public let sha256: String

    public init(text: String) {
        self.text = TextNormalizer.normalize(text)
        self.sha256 = SHA256.hash(data: Data(self.text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum DocumentTextExtractor {
    public static func extract(data: Data, fileExtension: String) async throws -> ExtractedDocument {
        guard data.count <= SecureImportStore.maximumBytes else { throw SecureImportError.fileTooLarge }
        switch fileExtension.lowercased() {
        case "txt":
            guard let text = String(data: data, encoding: .utf8) else { throw SecureImportError.unreadable }
            return ExtractedDocument(text: text)
        case "html", "htm":
            guard let html = String(data: data, encoding: .utf8) else { throw SecureImportError.unreadable }
            return ExtractedDocument(text: HTMLTextExtractor.text(from: html))
        case "eml":
            guard let source = String(data: data, encoding: .utf8) else { throw SecureImportError.unreadable }
            return ExtractedDocument(text: EMLTextExtractor.text(from: source))
        case "pdf":
            #if canImport(PDFKit)
            guard let document = PDFDocument(data: data), let text = document.string else {
                throw SecureImportError.unreadable
            }
            return ExtractedDocument(text: text)
            #else
            throw SecureImportError.unsupportedType
            #endif
        case "png", "jpg", "jpeg", "heic":
            #if canImport(Vision)
            return try await recognizeImage(data)
            #else
            throw SecureImportError.unsupportedType
            #endif
        default:
            throw SecureImportError.unsupportedType
        }
    }

    #if canImport(Vision)
    private static func recognizeImage(_ data: Data) async throws -> ExtractedDocument {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: ExtractedDocument(text: lines.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(data: data).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
}

public enum EMLTextExtractor {
    public static func text(from source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard let separator = normalized.range(of: "\n\n") else { return normalized }
        let body = String(normalized[separator.upperBound...])
        return decodeQuotedPrintable(body)
    }

    private static func decodeQuotedPrintable(_ value: String) -> String {
        var output = value.replacingOccurrences(of: "=\n", with: "")
        let pattern = #"=([0-9A-Fa-f]{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: output),
                  let hexRange = Range(match.range(at: 1), in: output),
                  let byte = UInt8(output[hexRange], radix: 16)
            else { continue }
            output.replaceSubrange(range, with: String(decoding: [byte], as: UTF8.self))
        }
        return output
    }
}
