import CoreModels
import Foundation
import SwiftData

/// Review-queue actions (spec: user review workflow). Every automatic
/// detection passes through here — nothing joins the ledger unconfirmed.
@MainActor
public final class CandidateReviewService {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Confirm as-detected. Only allowed when the candidate carries the
    /// complete billing shape; otherwise the user edits first.
    @discardableResult
    public func confirm(_ candidate: DetectionCandidate) throws -> Subscription? {
        guard let merchant = candidate.merchantName,
              let amount = candidate.amount,
              let currency = candidate.currencyCode,
              let frequency = candidate.billingFrequency
        else { return nil }

        let subscription = Subscription(
            merchantName: merchant,
            amount: amount,
            currencyCode: currency,
            billingFrequency: frequency,
            customInterval: candidate.customInterval,
            status: candidate.trialEndDate != nil ? .trial : .active,
            trialEndDate: candidate.trialEndDate,
            nextBillingDate: candidate.nextBillingDate ?? candidate.trialEndDate,
            detectionSource: .gmail,
            confidence: candidate.confidenceScore
        )
        subscription.reminderRules = defaultRules(for: subscription)
        context.insert(subscription)
        candidate.reviewStatus = .confirmed
        try context.save()
        return subscription
    }

    /// The user edited fields before confirming; the caller saved the
    /// subscription through the form — here we just resolve the candidate.
    public func markEditedAndConfirmed(_ candidate: DetectionCandidate) throws {
        candidate.reviewStatus = .edited
        try context.save()
    }

    /// Merge into the already-confirmed subscription it likely duplicates:
    /// refresh the billing date/amount from the newer evidence.
    public func merge(_ candidate: DetectionCandidate, into subscription: Subscription) throws {
        if let next = candidate.nextBillingDate, next != subscription.nextBillingDate {
            subscription.lastBillingDate = subscription.nextBillingDate
            subscription.nextBillingDate = next
        }
        if let amount = candidate.amount, amount != subscription.amount {
            subscription.amount = amount
        }
        subscription.updatedAt = .now
        candidate.reviewStatus = .merged
        try context.save()
    }

    /// Ignore: keep the record so the same message never resurfaces.
    public func ignore(_ candidate: DetectionCandidate) throws {
        candidate.reviewStatus = .ignored
        try context.save()
    }

    /// Not a subscription: negative signal for the rule registry.
    public func reject(_ candidate: DetectionCandidate) throws {
        candidate.reviewStatus = .rejected
        try context.save()
    }

    /// Bulk confirm — only candidates the spec allows (high confidence with a
    /// complete billing shape). Returns how many were confirmed.
    @discardableResult
    public func bulkConfirm(_ candidates: [DetectionCandidate]) throws -> Int {
        var confirmed = 0
        for candidate in candidates where candidate.isEligibleForBulkConfirm {
            if try confirm(candidate) != nil {
                confirmed += 1
            }
        }
        return confirmed
    }

    private func defaultRules(for subscription: Subscription) -> [ReminderRule] {
        let preferences = NotificationPreferences.load()
        var rules: [ReminderRule] = []
        if subscription.nextBillingDate != nil {
            rules.append(ReminderRule(
                reminderType: preferences.defaultLeadDays == 0 ? .billingDay : .beforeBilling,
                leadTimeDays: preferences.defaultLeadDays,
                timeOfDayMinutes: preferences.defaultTimeOfDayMinutes
            ))
        }
        if subscription.trialEndDate != nil {
            for lead in preferences.trialLeadDays {
                rules.append(ReminderRule(
                    reminderType: .trialEnd,
                    leadTimeDays: lead,
                    timeOfDayMinutes: preferences.defaultTimeOfDayMinutes
                ))
            }
        }
        return rules
    }
}
