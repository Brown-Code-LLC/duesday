import Foundation

/// Provenance for one extracted field of a detection candidate.
/// The pipeline never invents values — every non-nil field on a
/// ``DetectionCandidate`` must be backed by at least one evidence entry
/// (spec: subscription-detection pipeline).
public struct DetectionEvidence: Hashable, Codable, Sendable {
    public enum Field: String, Codable, Sendable, CaseIterable {
        case merchant
        case amount
        case currency
        case frequency
        case nextBillingDate
        case trialEnd
        case cancellation
        case priceChange
    }

    public enum Reason: String, Codable, Sendable, CaseIterable {
        case trustedSenderDomain
        case recurringPhrase
        case labeledAmount
        case explicitInterval
        case explicitRenewalDate
        case repeatedReceipt
        case cancellationLanguage
        case headerBodyAgreement
        case merchantPattern
        case documentText
        case userProvided
    }

    /// Maximum length of a stored snippet — evidence is a redacted excerpt,
    /// never a retained email body (privacy model).
    public static let maxSnippetLength = 160

    public var field: Field
    public var reason: Reason
    public var snippet: String
    public var weight: Double

    public init(field: Field, reason: Reason, snippet: String, weight: Double) {
        self.field = field
        self.reason = reason
        self.snippet = String(snippet.prefix(Self.maxSnippetLength))
        self.weight = weight.clamped(to: 0...1)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
