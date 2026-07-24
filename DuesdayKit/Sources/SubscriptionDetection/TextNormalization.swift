import Foundation

/// Deterministic HTML → text reduction for the detection pipeline. This is a
/// sanitizer in the strictest sense: scripts/styles are dropped wholesale,
/// every tag is stripped, entities are decoded, and only plain text survives.
/// Nothing here is ever rendered — display sanitization is a separate concern.
public enum HTMLTextExtractor {
    public static func text(from html: String) -> String {
        var working = html

        // Drop script/style/head blocks entirely, including contents.
        for container in ["script", "style", "head", "title"] {
            working = working.replacingOccurrences(
                of: "<\(container)[^>]*>[\\s\\S]*?</\(container)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // HTML comments (tracking markers often hide here).
        working = working.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: " ",
            options: .regularExpression
        )
        // Block-level closers become line breaks so labels stay on their line.
        working = working.replacingOccurrences(
            of: "</(p|div|tr|li|h[1-6]|table|section)>|<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Every remaining tag.
        working = working.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        working = decodeEntities(working)
        return TextNormalizer.normalize(working)
    }

    private static let entities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
        "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
        "&euro;": "€", "&pound;": "£", "&yen;": "¥", "&dollar;": "$",
        "&copy;": "©", "&reg;": "®", "&trade;": "™", "&hellip;": "…",
        "&rsquo;": "'", "&lsquo;": "'", "&rdquo;": "\"", "&ldquo;": "\"",
    ]

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Numeric entities: &#8364; and &#x20AC;
        for match in result.matches(pattern: "&#(x?)([0-9a-fA-F]{1,6});").reversed() {
            let isHex = !match.group(1, in: result).isEmpty
            let digits = match.group(2, in: result)
            let value = UInt32(digits, radix: isHex ? 16 : 10)
            if let value, let scalar = Unicode.Scalar(value), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return result
    }
}

public enum TextNormalizer {
    /// Collapses whitespace within lines, trims, drops empty lines.
    public static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - Small regex conveniences (NSRegularExpression, cached)

final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        cache[pattern] = regex
        return regex
    }
}

extension String {
    func matches(pattern: String) -> [NSTextCheckingResult] {
        guard let regex = RegexCache.shared.regex(pattern) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self))
    }

    func firstMatch(pattern: String) -> NSTextCheckingResult? {
        matches(pattern: pattern).first
    }

    func containsPattern(_ pattern: String) -> Bool {
        firstMatch(pattern: pattern) != nil
    }
}

extension NSTextCheckingResult {
    func group(_ index: Int, in text: String) -> String {
        guard index < numberOfRanges, let range = Range(range(at: index), in: text) else { return "" }
        return String(text[range])
    }
}
