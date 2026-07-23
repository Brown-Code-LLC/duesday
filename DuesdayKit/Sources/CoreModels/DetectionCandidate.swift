import Foundation
import SwiftData

/// An automatically detected possible subscription awaiting user review.
/// Every extracted field is optional: missing means unknown — the pipeline
/// never invents values. Non-nil fields must be backed by ``DetectionEvidence``.
@Model
public final class DetectionCandidate {
    @Attribute(.unique) public var id: UUID
    /// `UserAccount.id` for email detections; nil for document imports.
    public var sourceAccountID: UUID?
    public var sourceMessageID: String?
    public var merchantName: String?
    public var amount: Decimal?
    public var currencyCode: String?
    public var billingFrequencyRaw: String?
    public var customInterval: CustomInterval?
    public var detectedDate: Date
    public var nextBillingDate: Date?
    public var trialEndDate: Date?
    public var evidence: [DetectionEvidence]
    public var confidenceScore: Double
    /// Per-field confidence keyed by `DetectionEvidence.Field.rawValue`.
    public var fieldConfidence: [String: Double]
    public var reviewStatusRaw: String
    public var possibleDuplicateSubscriptionID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceAccountID: UUID? = nil,
        sourceMessageID: String? = nil,
        merchantName: String? = nil,
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        billingFrequency: BillingFrequency? = nil,
        customInterval: CustomInterval? = nil,
        detectedDate: Date = .now,
        nextBillingDate: Date? = nil,
        trialEndDate: Date? = nil,
        evidence: [DetectionEvidence] = [],
        confidenceScore: Double = 0,
        fieldConfidence: [String: Double] = [:],
        reviewStatus: ReviewStatus = .pending,
        possibleDuplicateSubscriptionID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceAccountID = sourceAccountID
        self.sourceMessageID = sourceMessageID
        self.merchantName = merchantName
        self.amount = amount
        self.currencyCode = currencyCode?.uppercased()
        self.billingFrequencyRaw = billingFrequency?.rawValue
        self.customInterval = customInterval
        self.detectedDate = detectedDate
        self.nextBillingDate = nextBillingDate
        self.trialEndDate = trialEndDate
        self.evidence = evidence
        self.confidenceScore = confidenceScore.clamped(to: 0...1)
        self.fieldConfidence = fieldConfidence
        self.reviewStatusRaw = reviewStatus.rawValue
        self.possibleDuplicateSubscriptionID = possibleDuplicateSubscriptionID
        self.createdAt = createdAt
    }
}

extension DetectionCandidate {
    public var billingFrequency: BillingFrequency? {
        get { billingFrequencyRaw.flatMap(BillingFrequency.init(rawValue:)) }
        set { billingFrequencyRaw = newValue?.rawValue }
    }

    public var reviewStatus: ReviewStatus {
        get { ReviewStatus(rawValue: reviewStatusRaw) ?? .pending }
        set { reviewStatusRaw = newValue.rawValue }
    }

    /// Threshold at or above which bulk confirmation is permitted
    /// (spec: user review workflow).
    public static let bulkConfirmThreshold: Double = 0.85

    public var isEligibleForBulkConfirm: Bool {
        confidenceScore >= Self.bulkConfirmThreshold
            && merchantName != nil
            && amount != nil
            && currencyCode != nil
            && billingFrequency != nil
    }
}
