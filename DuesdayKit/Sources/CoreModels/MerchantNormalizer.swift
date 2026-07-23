import Foundation

/// Canonicalizes merchant names for duplicate matching:
/// "Netflix, Inc." and "NETFLIX Inc" both normalize to "netflix".
public enum MerchantNormalizer {
    private static let legalSuffixes: Set<String> = [
        "inc", "incorporated", "llc", "ltd", "limited", "co", "corp",
        "corporation", "gmbh", "sa", "sarl", "bv", "plc", "ag", "pty", "oy",
    ]

    public static func normalize(_ raw: String) -> String {
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let tokens = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var kept = tokens
        while let last = kept.last, legalSuffixes.contains(last), kept.count > 1 {
            kept.removeLast()
        }
        return kept.joined(separator: " ")
    }
}
