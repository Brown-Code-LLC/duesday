import CoreModels
import Foundation

/// Field extractors — each returns a value plus the evidence snippet that
/// justifies it. Missing means unknown; nothing is guessed.

// MARK: - Merchant

public enum MerchantDetector {
    /// Known merchant sender domains → canonical names. Grows with the rule
    /// registry; matching here earns `trustedSenderDomain` evidence.
    static let domainRegistry: [String: String] = [
        "netflix.com": "Netflix",
        "spotify.com": "Spotify",
        "apple.com": "Apple",
        "google.com": "Google",
        "youtube.com": "YouTube",
        "amazon.com": "Amazon",
        "adobe.com": "Adobe",
        "hulu.com": "Hulu",
        "paramountplus.com": "Paramount+",
        "nytimes.com": "The New York Times",
        "dropbox.com": "Dropbox",
        "notion.so": "Notion",
        "github.com": "GitHub",
        "openai.com": "OpenAI",
        "audible.com": "Audible",
        "squarespace.com": "Squarespace",
        "disneyplus.com": "Disney+",
        "medium.com": "Medium",
        "patreon.com": "Patreon",
        "duolingo.com": "Duolingo",
    ]

    public struct Result: Sendable {
        public let name: String
        public let domain: String?
        public let trusted: Bool
        public let confidence: Double
        public let snippet: String
    }

    public static func detect(from fromHeader: String) -> Result? {
        // "Display Name <mailbox@sub.domain.tld>" or bare address.
        let address: String
        var displayName: String?
        if let match = fromHeader.firstMatch(pattern: "^\\s*\"?([^\"<]*?)\"?\\s*<([^>]+)>") {
            let name = match.group(1, in: fromHeader).trimmingCharacters(in: .whitespaces)
            displayName = name.isEmpty ? nil : name
            address = match.group(2, in: fromHeader)
        } else {
            address = fromHeader.trimmingCharacters(in: .whitespaces)
        }
        guard let atIndex = address.lastIndex(of: "@") else {
            guard let displayName else { return nil }
            return Result(name: displayName, domain: nil, trusted: false, confidence: 0.5, snippet: fromHeader)
        }
        let host = String(address[address.index(after: atIndex)...]).lowercased()

        // Registrable domain: last two labels (good enough for the registry).
        let labels = host.split(separator: ".")
        let registrable = labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : host

        if let known = domainRegistry[registrable] {
            return Result(name: known, domain: registrable, trusted: true, confidence: 0.95, snippet: fromHeader)
        }
        if let displayName, !isGenericSenderName(displayName) {
            return Result(name: cleaned(displayName), domain: registrable, trusted: false, confidence: 0.7, snippet: fromHeader)
        }
        // Derive from the domain label.
        guard let label = labels.dropLast().last ?? labels.first else { return nil }
        let derived = label.replacingOccurrences(of: "-", with: " ").capitalized
        return Result(name: derived, domain: registrable, trusted: false, confidence: 0.5, snippet: fromHeader)
    }

    private static func isGenericSenderName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["billing", "receipts", "no-reply", "noreply", "support", "team", "info", "notifications"]
            .contains { lowered == $0 }
    }

    private static func cleaned(_ name: String) -> String {
        var result = name
        for noise in ["Billing", "Receipts", "Team", "Support", "No-Reply", "Noreply"] {
            result = result.replacingOccurrences(of: " \(noise)", with: "", options: .caseInsensitive)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Amount & currency

public enum AmountExtractor {
    public struct Result: Sendable {
        public let amount: Decimal
        public let currencyCode: String
        public let labeled: Bool
        public let snippet: String
    }

    private static let symbolCurrencies: [(symbol: String, code: String)] = [
        ("US$", "USD"), ("CA$", "CAD"), ("A$", "AUD"), ("$", "USD"),
        ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₦", "NGN"), ("₹", "INR"),
    ]
    private static let codePattern = "\\b(USD|EUR|GBP|CAD|AUD|JPY|CHF|SEK|NOK|DKK|NGN|GHS|INR|BRL|MXN)\\b"
    private static let numberPattern = "([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?|[0-9]+)"
    /// Words that mark the charged total rather than a line item.
    private static let labelPattern =
        "(total|amount due|amount charged|amount|you paid|payment of|charged|billed|price|now|renews at|for just)"

    public static func detect(in text: String) -> Result? {
        var best: Result?
        for line in text.components(separatedBy: "\n") {
            let labeled = line.containsPattern(labelPattern)
            for candidate in amounts(in: line) {
                let result = Result(
                    amount: candidate.amount,
                    currencyCode: candidate.code,
                    labeled: labeled,
                    snippet: String(line.prefix(120))
                )
                // Prefer labeled amounts; among equals prefer the larger
                // (totals exceed line items).
                if let current = best {
                    if (labeled && !current.labeled)
                        || (labeled == current.labeled && result.amount > current.amount) {
                        best = result
                    }
                } else {
                    best = result
                }
            }
        }
        return best
    }

    private static func amounts(in line: String) -> [(amount: Decimal, code: String)] {
        var found: [(Decimal, String)] = []
        for (symbol, code) in symbolCurrencies {
            let escaped = NSRegularExpression.escapedPattern(for: symbol)
            for match in line.matches(pattern: "\(escaped)\\s?\(numberPattern)") {
                if let amount = parseDecimal(match.group(1, in: line), noMinor: code == "JPY") {
                    found.append((amount, code))
                }
            }
            // Once "$" matched, don't re-match the "US$" prefix cases twice.
            if !found.isEmpty && symbol == "$" { break }
        }
        for match in line.matches(pattern: "\(codePattern)\\s?\(numberPattern)") {
            if let amount = parseDecimal(match.group(2, in: line), noMinor: match.group(1, in: line) == "JPY") {
                found.append((amount, match.group(1, in: line).uppercased()))
            }
        }
        return found.filter { $0.0 > 0 && $0.0 < 100_000 }
    }

    /// Handles both `1,234.56` and `1.234,56` conventions.
    public static func parseDecimal(_ raw: String, noMinor: Bool = false) -> Decimal? {
        var cleaned = raw
        let lastComma = cleaned.range(of: ",", options: .backwards)?.lowerBound
        let lastDot = cleaned.range(of: ".", options: .backwards)?.lowerBound

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            if comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        case (let comma?, nil):
            let minor = cleaned.distance(from: cleaned.index(after: comma), to: cleaned.endIndex)
            cleaned = minor == 2 && !noMinor
                ? cleaned.replacingOccurrences(of: ",", with: ".")
                : cleaned.replacingOccurrences(of: ",", with: "")
        default:
            break
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Billing frequency

public enum FrequencyExtractor {
    public struct Result: Sendable {
        public let frequency: BillingFrequency
        public let customInterval: CustomInterval?
        public let snippet: String
    }

    public static func detect(in text: String) -> Result? {
        let patterns: [(String, BillingFrequency)] = [
            ("(billed|renews?|charged)\\s+monthly|per month|/\\s?mo\\b|a month|each month|monthly (plan|subscription|membership)", .monthly),
            ("(billed|renews?|charged)\\s+(annually|yearly)|per year|/\\s?yr\\b|a year|annual (plan|subscription|membership)|yearly (plan|subscription)", .annual),
            ("quarterly|every 3 months|per quarter", .quarterly),
            ("every 6 months|semi-?annual|twice a year", .semiannual),
            ("(billed|renews?|charged)\\s+weekly|per week|/\\s?wk\\b|a week|weekly (plan|subscription)", .weekly),
        ]
        for (pattern, frequency) in patterns {
            if let match = text.firstMatch(pattern: pattern) {
                return Result(
                    frequency: frequency,
                    customInterval: nil,
                    snippet: snippet(around: match, in: text)
                )
            }
        }
        if let match = text.firstMatch(pattern: "every\\s+(\\d{1,3})\\s+(day|week|month|year)s?") {
            let count = Int(match.group(1, in: text)) ?? 1
            let unit: CustomInterval.Unit? = switch match.group(2, in: text).lowercased() {
            case "day": .day
            case "week": .week
            case "month": .month
            case "year": .year
            default: nil
            }
            if let unit, count > 1 {
                return Result(
                    frequency: .custom,
                    customInterval: CustomInterval(count: count, unit: unit),
                    snippet: snippet(around: match, in: text)
                )
            }
        }
        return nil
    }

    private static func snippet(around match: NSTextCheckingResult, in text: String) -> String {
        guard let range = Range(match.range, in: text) else { return "" }
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Dates

public enum DateExtractor {
    private static let formats = [
        "MMMM d, yyyy", "MMM d, yyyy", "d MMMM yyyy", "d MMM yyyy",
        "yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy",
    ]

    static func parse(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let datePattern =
        "([A-Za-z]{3,9} \\d{1,2}, \\d{4}|\\d{1,2} [A-Za-z]{3,9} \\d{4}|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}/\\d{1,2}/\\d{4})"

    public struct Result: Sendable {
        public let date: Date
        public let snippet: String
    }

    /// Finds a date that appears near one of the context keywords.
    public static func detect(in text: String, context: String) -> Result? {
        let pattern = "\(context)[^\\n]{0,60}?\(datePattern)"
        guard let match = text.firstMatch(pattern: pattern) else { return nil }
        // The date pattern is the final capture group; earlier groups belong
        // to the context alternation.
        let raw = match.group(match.numberOfRanges - 1, in: text)
        guard let date = parse(raw) else { return nil }
        let snippet = match.group(0, in: text).replacingOccurrences(of: "\n", with: " ")
        return Result(date: date, snippet: String(snippet.prefix(120)))
    }

    public static let renewalContext =
        "(next (billing|payment|charge|renewal)( date)?|renews? (on|date)|will renew( on)?|auto-?renews? on|due on|renewal date)[:\\s]"
    public static let trialContext =
        "(trial (ends?|will end|period ends?|expires?)( on)?)[:\\s]"
}

// MARK: - Phrase detectors

public enum PhraseDetectors {
    public static func recurringPhrase(in text: String) -> String? {
        firstSnippet(
            in: text,
            pattern: "(subscription|auto-?renew|recurring (payment|charge)|will (automatically )?renew|your (plan|membership)|renews (automatically|monthly|annually|yearly))"
        )
    }

    public static func trialPhrase(in text: String) -> String? {
        firstSnippet(in: text, pattern: "(free trial|trial period|your trial|trial (ends|will end|expires))")
    }

    public static func cancellationPhrase(in text: String) -> String? {
        firstSnippet(
            in: text,
            pattern: "((subscription|membership|plan) (has been|was|is now) cancel(l)?ed|cancellation (confirmed|confirmation)|we('|’)ve cancel(l)?ed)"
        )
    }

    public static func priceChangePhrase(in text: String) -> String? {
        firstSnippet(
            in: text,
            pattern: "(price (increase|change|is (changing|increasing))|new price|price will (increase|change|go up)|will (increase|change) to)"
        )
    }

    public static func failedPaymentPhrase(in text: String) -> String? {
        firstSnippet(
            in: text,
            pattern: "(payment (failed|was declined|declined|unsuccessful)|could(n't| not) process your payment|update your payment (method|details))"
        )
    }

    public static func refundPhrase(in text: String) -> String? {
        firstSnippet(in: text, pattern: "(refund (issued|processed|confirmation)|has been refunded|your refund)")
    }

    /// Marketing / shipping signals that veto candidate creation when no
    /// billing evidence exists (false-positive guard).
    public static func marketingPhrase(in text: String) -> String? {
        firstSnippet(
            in: text,
            pattern: "(\\d{1,2}% off|limited time (deal|offer)|flash sale|has (shipped|been delivered)|track your (package|order)|out for delivery)"
        )
    }

    private static func firstSnippet(in text: String, pattern: String) -> String? {
        guard let match = text.firstMatch(pattern: pattern) else { return nil }
        let raw = match.group(0, in: text)
        return String(raw.prefix(120))
    }
}
