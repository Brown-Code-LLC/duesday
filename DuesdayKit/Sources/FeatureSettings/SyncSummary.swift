import Foundation

/// Result of one manual sync pass, surfaced in the accounts UI so backfill
/// progress is visible instead of silent.
public struct SyncSummary: Sendable {
    public let scanned: Int
    public let created: Int
    /// False while older matching mail remains — another pass continues the
    /// backfill from where this one stopped.
    public let backfillComplete: Bool

    public init(scanned: Int, created: Int, backfillComplete: Bool) {
        self.scanned = scanned
        self.created = created
        self.backfillComplete = backfillComplete
    }

    public var userDescription: String {
        var text = "Scanned \(scanned) message\(scanned == 1 ? "" : "s") · \(created) for review"
        text += backfillComplete
            ? " · caught up"
            : " · more to scan — sync again"
        return text
    }
}

/// Sync cursor encoding shared by the provider services: a backfill search
/// position ("search:<pageToken>") until the historical sweep completes, then
/// the provider's incremental cursor ("incr:<cursor>"). Legacy unprefixed
/// values are treated as incremental cursors.
enum SyncCursorState {
    case backfill(pageToken: String?)
    case incremental(String)

    static func parse(_ raw: String?) -> SyncCursorState {
        guard let raw, !raw.isEmpty else { return .backfill(pageToken: nil) }
        if raw.hasPrefix("search:") {
            let token = String(raw.dropFirst("search:".count))
            return .backfill(pageToken: token.isEmpty ? nil : token)
        }
        if raw.hasPrefix("incr:") {
            return .incremental(String(raw.dropFirst("incr:".count)))
        }
        return .incremental(raw)
    }

    static func encodeBackfill(_ pageToken: String?) -> String {
        "search:\(pageToken ?? "")"
    }

    static func encodeIncremental(_ cursor: String) -> String {
        "incr:\(cursor)"
    }
}
