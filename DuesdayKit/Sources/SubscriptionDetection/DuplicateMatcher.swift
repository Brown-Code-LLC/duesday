import CoreModels
import Foundation

/// Duplicate resolution before candidate creation (spec: detection pipeline).
/// Comparison ladder: provider message ID → pending candidate with the same
/// shape → existing confirmed subscription.
public enum DuplicateMatcher {
    public enum Verdict: Sendable, Equatable {
        /// Same message or same receipt already queued — don't create again.
        case drop(reason: String)
        /// Likely the same subscription the user already confirmed; create the
        /// candidate but link it for merge-review.
        case possibleDuplicate(subscriptionID: UUID)
        case unique
    }

    public struct ExistingCandidate: Sendable {
        public let sourceMessageID: String?
        public let normalizedMerchant: String?
        public let amount: Decimal?
        public let currencyCode: String?

        public init(sourceMessageID: String?, normalizedMerchant: String?, amount: Decimal?, currencyCode: String?) {
            self.sourceMessageID = sourceMessageID
            self.normalizedMerchant = normalizedMerchant
            self.amount = amount
            self.currencyCode = currencyCode
        }
    }

    public struct ExistingSubscription: Sendable {
        public let id: UUID
        public let normalizedMerchant: String
        public let amount: Decimal
        public let currencyCode: String
        public let frequency: BillingFrequency

        public init(id: UUID, normalizedMerchant: String, amount: Decimal, currencyCode: String, frequency: BillingFrequency) {
            self.id = id
            self.normalizedMerchant = normalizedMerchant
            self.amount = amount
            self.currencyCode = currencyCode
            self.frequency = frequency
        }
    }

    public static func evaluate(
        draft: CandidateDraft,
        existingCandidates: [ExistingCandidate],
        existingSubscriptions: [ExistingSubscription]
    ) -> Verdict {
        // 1. Exact message replay.
        if existingCandidates.contains(where: { $0.sourceMessageID == draft.sourceMessageID }) {
            return .drop(reason: "Message already processed")
        }

        let normalizedMerchant = draft.merchantName.map(MerchantNormalizer.normalize)

        // 2. Duplicate receipt: same merchant + amount + currency already queued.
        if let normalizedMerchant, let amount = draft.amount, let currency = draft.currencyCode {
            let duplicate = existingCandidates.contains { candidate in
                candidate.normalizedMerchant == normalizedMerchant
                    && candidate.currencyCode == currency
                    && candidate.amount.map { amountsMatch($0, amount) } == true
            }
            if duplicate {
                return .drop(reason: "Duplicate receipt already in review")
            }
        }

        // 3. Existing subscription: merchant + currency + close amount
        //    (and interval agreement when both are known).
        if let normalizedMerchant {
            for subscription in existingSubscriptions where subscription.normalizedMerchant == normalizedMerchant {
                let currencyMatches = draft.currencyCode == nil
                    || draft.currencyCode == subscription.currencyCode
                let amountMatches = draft.amount.map { amountsMatch($0, subscription.amount) } ?? true
                let intervalMatches = draft.frequency == nil
                    || draft.frequency == subscription.frequency
                if currencyMatches && amountMatches && intervalMatches {
                    return .possibleDuplicate(subscriptionID: subscription.id)
                }
            }
        }
        return .unique
    }

    /// Within 2% — receipts sometimes include sub-cent tax rounding.
    static func amountsMatch(_ a: Decimal, _ b: Decimal) -> Bool {
        guard a > 0, b > 0 else { return a == b }
        let difference = abs(a - b)
        let tolerance = max(a, b) * Decimal(string: "0.02")!
        return difference <= tolerance
    }
}
