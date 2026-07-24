import Authentication
import EmailProviders
import Foundation

// Codable mirror of the Gmail REST message resource — only the fields we use.

struct GmailProfilePayload: Decodable {
    let emailAddress: String
    let historyId: String?
}

struct GmailMessageListPayload: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let messages: [Item]?
    let nextPageToken: String?
}

struct GmailHistoryPayload: Decodable {
    struct History: Decodable {
        struct Added: Decodable {
            struct Message: Decodable {
                let id: String
            }

            let message: Message
        }

        let messagesAdded: [Added]?
    }

    let history: [History]?
    let historyId: String?
    let nextPageToken: String?
}

struct GmailMessagePayload: Decodable {
    struct Header: Decodable {
        let name: String
        let value: String
    }

    struct Body: Decodable {
        let data: String?
        let size: Int?
    }

    final class Part: Decodable {
        let mimeType: String?
        let body: Body?
        let headers: [Header]?
        let parts: [Part]?
    }

    let id: String
    let internalDate: String?
    let snippet: String?
    let payload: Part?
}

enum GmailMessageDecoder {
    static func metadata(from payload: GmailMessagePayload) -> MessageMetadata {
        let headers = payload.payload?.headers ?? []
        func header(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let date = payload.internalDate
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        return MessageMetadata(
            id: payload.id,
            from: header("From") ?? "",
            subject: header("Subject") ?? "",
            date: date,
            snippet: payload.snippet
        )
    }

    /// Walks the MIME tree collecting the first text/plain and text/html
    /// bodies (base64url-encoded per the Gmail API).
    static func content(from payload: GmailMessagePayload) -> MessageContent {
        var plain: String?
        var html: String?

        func visit(_ part: GmailMessagePayload.Part?) {
            guard let part else { return }
            if let mime = part.mimeType?.lowercased(), let data = part.body?.data,
               let decoded = Data(base64URLEncoded: data).map({ String(decoding: $0, as: UTF8.self) }) {
                if mime.hasPrefix("text/plain"), plain == nil {
                    plain = decoded
                } else if mime.hasPrefix("text/html"), html == nil {
                    html = decoded
                }
            }
            for child in part.parts ?? [] {
                visit(child)
            }
        }
        visit(payload.payload)

        return MessageContent(
            metadata: metadata(from: payload),
            plainText: plain,
            html: html
        )
    }
}
