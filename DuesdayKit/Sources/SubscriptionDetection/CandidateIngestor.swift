import CoreModels
import Foundation
import SwiftData

/// Persists pipeline output as review-queue candidates, applying the
/// duplicate ladder against stored candidates and confirmed subscriptions.
/// MainActor because it writes through the main model context.
@MainActor
public final class CandidateIngestor {
    public enum Result: Equatable {
        case created(UUID)
        case skipped(String)
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func ingest(_ outcome: DetectionOutcome, sourceAccountID: UUID?) throws -> Result {
        guard case .candidate(let draft) = outcome else {
            if case .notSubscription(let reason) = outcome {
                return .skipped(reason)
            }
            return .skipped("No candidate")
        }

        let existingCandidates = try context.fetch(FetchDescriptor<DetectionCandidate>())
            .map { candidate in
                DuplicateMatcher.ExistingCandidate(
                    sourceMessageID: candidate.sourceMessageID,
                    normalizedMerchant: candidate.merchantName.map(MerchantNormalizer.normalize),
                    amount: candidate.amount,
                    currencyCode: candidate.currencyCode
                )
            }
        let existingSubscriptions = try context.fetch(FetchDescriptor<Subscription>())
            .map { subscription in
                DuplicateMatcher.ExistingSubscription(
                    id: subscription.id,
                    normalizedMerchant: subscription.normalizedMerchantName,
                    amount: subscription.amount,
                    currencyCode: subscription.currencyCode,
                    frequency: subscription.billingFrequency
                )
            }

        let verdict = DuplicateMatcher.evaluate(
            draft: draft,
            existingCandidates: existingCandidates,
            existingSubscriptions: existingSubscriptions
        )

        var possibleDuplicateID: UUID?
        switch verdict {
        case .drop(let reason):
            return .skipped(reason)
        case .possibleDuplicate(let subscriptionID):
            possibleDuplicateID = subscriptionID
        case .unique:
            break
        }

        let candidate = DetectionCandidate(
            sourceAccountID: sourceAccountID,
            sourceMessageID: draft.sourceMessageID,
            merchantName: draft.merchantName,
            amount: draft.amount,
            currencyCode: draft.currencyCode,
            billingFrequency: draft.frequency,
            customInterval: draft.customInterval,
            detectedDate: draft.messageDate ?? .now,
            nextBillingDate: draft.nextBillingDate,
            trialEndDate: draft.trialEndDate,
            evidence: draft.evidence,
            confidenceScore: draft.confidence,
            fieldConfidence: draft.fieldConfidence,
            possibleDuplicateSubscriptionID: possibleDuplicateID
        )
        context.insert(candidate)
        try context.save()
        return .created(candidate.id)
    }
}
