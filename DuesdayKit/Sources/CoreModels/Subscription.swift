import Foundation
import SwiftData

/// A confirmed recurring commitment: subscription, membership, bill, or trial.
/// Enum-typed fields used in predicates are stored as raw strings (ADR-2).
@Model
public final class Subscription {
    @Attribute(.unique) public var id: UUID
    public var merchantName: String
    /// Canonical merchant key for duplicate matching — always derived via
    /// ``MerchantNormalizer``; kept in sync by `update(merchantName:)`.
    public var normalizedMerchantName: String
    public var planName: String?
    public var amount: Decimal
    public var currencyCode: String
    public var billingFrequencyRaw: String
    public var customInterval: CustomInterval?
    public var statusRaw: String
    public var startDate: Date?
    public var trialEndDate: Date?
    public var nextBillingDate: Date?
    public var lastBillingDate: Date?
    public var introductoryPrice: Decimal?
    public var regularPrice: Decimal?
    public var introductoryPriceEndDate: Date?
    public var categoryRaw: String
    /// Free-text label like "Visa ••4242" — never a full card number.
    public var paymentMethodLabel: String?
    public var ownershipTypeRaw: String
    public var websiteURL: URL?
    public var cancellationURL: URL?
    public var cancellationInstructions: String?
    public var notes: String?
    public var detectionSourceRaw: String
    /// Candidate-level confidence at confirmation time; nil for manual entries.
    public var confidence: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \RenewalEvent.subscription)
    public var renewalEvents: [RenewalEvent]

    @Relationship(deleteRule: .cascade, inverse: \ReminderRule.subscription)
    public var reminderRules: [ReminderRule]

    public init(
        id: UUID = UUID(),
        merchantName: String,
        planName: String? = nil,
        amount: Decimal,
        currencyCode: String,
        billingFrequency: BillingFrequency,
        customInterval: CustomInterval? = nil,
        status: SubscriptionStatus = .active,
        startDate: Date? = nil,
        trialEndDate: Date? = nil,
        nextBillingDate: Date? = nil,
        lastBillingDate: Date? = nil,
        introductoryPrice: Decimal? = nil,
        regularPrice: Decimal? = nil,
        introductoryPriceEndDate: Date? = nil,
        category: SubscriptionCategory = .other,
        paymentMethodLabel: String? = nil,
        ownershipType: OwnershipType = .personal,
        websiteURL: URL? = nil,
        cancellationURL: URL? = nil,
        cancellationInstructions: String? = nil,
        notes: String? = nil,
        detectionSource: DetectionSource = .manual,
        confidence: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.merchantName = merchantName
        self.normalizedMerchantName = MerchantNormalizer.normalize(merchantName)
        self.planName = planName
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.billingFrequencyRaw = billingFrequency.rawValue
        self.customInterval = billingFrequency == .custom ? customInterval : nil
        self.statusRaw = status.rawValue
        self.startDate = startDate
        self.trialEndDate = trialEndDate
        self.nextBillingDate = nextBillingDate
        self.lastBillingDate = lastBillingDate
        self.introductoryPrice = introductoryPrice
        self.regularPrice = regularPrice
        self.introductoryPriceEndDate = introductoryPriceEndDate
        self.categoryRaw = category.rawValue
        self.paymentMethodLabel = paymentMethodLabel
        self.ownershipTypeRaw = ownershipType.rawValue
        self.websiteURL = websiteURL
        self.cancellationURL = cancellationURL
        self.cancellationInstructions = cancellationInstructions
        self.notes = notes
        self.detectionSourceRaw = detectionSource.rawValue
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.renewalEvents = []
        self.reminderRules = []
    }
}

// MARK: - Typed accessors

extension Subscription {
    public var billingFrequency: BillingFrequency {
        get { BillingFrequency(rawValue: billingFrequencyRaw) ?? .monthly }
        set {
            billingFrequencyRaw = newValue.rawValue
            if newValue != .custom { customInterval = nil }
        }
    }

    public var status: SubscriptionStatus {
        get { SubscriptionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var category: SubscriptionCategory {
        get { SubscriptionCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    public var ownershipType: OwnershipType {
        get { OwnershipType(rawValue: ownershipTypeRaw) ?? .personal }
        set { ownershipTypeRaw = newValue.rawValue }
    }

    public var detectionSource: DetectionSource {
        get { DetectionSource(rawValue: detectionSourceRaw) ?? .manual }
        set { detectionSourceRaw = newValue.rawValue }
    }

    public var money: Money {
        Money(amount: amount, currencyCode: currencyCode)
    }

    public var isArchived: Bool { archivedAt != nil }

    /// Estimated normalized monthly cost; nil when the interval is unknown.
    public var estimatedMonthlyCost: Decimal? {
        SpendingMath.monthlyEstimate(
            amount: amount,
            frequency: billingFrequency,
            customInterval: customInterval
        )
    }

    /// Estimated annualized cost; nil when the interval is unknown.
    public var estimatedAnnualCost: Decimal? {
        SpendingMath.annualEstimate(
            amount: amount,
            frequency: billingFrequency,
            customInterval: customInterval
        )
    }

    /// Renames the merchant, keeping the normalized key consistent.
    public func update(merchantName newName: String) {
        merchantName = newName
        normalizedMerchantName = MerchantNormalizer.normalize(newName)
        updatedAt = .now
    }

    /// Rolls `nextBillingDate` forward so it is on or after `reference`,
    /// using the stored frequency. No-op when the schedule is unknown.
    public func rollNextBillingDate(onOrAfter reference: Date = .now, calendar: Calendar = .current) {
        guard let anchor = nextBillingDate ?? startDate else { return }
        guard let next = BillingSchedule.nextDate(
            onOrAfter: reference,
            anchor: anchor,
            frequency: billingFrequency,
            customInterval: customInterval,
            calendar: calendar
        ) else { return }
        if next != nextBillingDate {
            lastBillingDate = nextBillingDate
            nextBillingDate = next
            updatedAt = .now
        }
    }
}
