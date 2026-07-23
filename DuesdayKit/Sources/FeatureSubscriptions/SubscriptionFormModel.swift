import CoreModels
import Foundation
import Observation
import Persistence

/// Presentation model for manual subscription entry and editing.
/// Holds all validation logic so it is unit-testable without SwiftUI
/// (ADR-5: view models only where there is real presentation logic).
@Observable
public final class SubscriptionFormModel {
    public enum Mode {
        case create
        case edit(Subscription)
    }

    public enum ValidationError: LocalizedError, Equatable {
        case missingMerchant
        case missingAmount
        case nonPositiveAmount
        case invalidCustomInterval
        case missingIntroductoryPrice
        case invalidWebsiteURL
        case invalidCancellationURL

        public var errorDescription: String? {
            switch self {
            case .missingMerchant: "Enter the merchant or service name."
            case .missingAmount: "Enter the billing amount."
            case .nonPositiveAmount: "The amount must be greater than zero."
            case .invalidCustomInterval: "Custom billing needs an interval of at least 1."
            case .missingIntroductoryPrice: "Enter the price this changes to, or turn off introductory pricing."
            case .invalidWebsiteURL: "The website link must be a valid http(s) URL."
            case .invalidCancellationURL: "The cancellation link must be a valid http(s) URL."
            }
        }
    }

    public let mode: Mode

    public var merchantName: String
    public var planName: String
    public var amount: Decimal?
    public var currencyCode: String
    public var frequency: BillingFrequency
    public var customCount: Int
    public var customUnit: CustomInterval.Unit
    public var category: SubscriptionCategory
    public var status: SubscriptionStatus
    public var ownership: OwnershipType
    public var hasNextBillingDate: Bool
    public var nextBillingDate: Date
    public var hasStartDate: Bool
    public var startDate: Date
    public var hasTrialEnd: Bool
    public var trialEndDate: Date
    /// Introductory pricing: the current `amount` is the promo price and
    /// `regularPrice` takes over on `introEndDate` (spec: intro-price disclosure).
    public var hasIntroPricing: Bool
    public var regularPrice: Decimal?
    public var introEndDate: Date
    public var paymentMethodLabel: String
    public var websiteURLText: String
    public var cancellationURLText: String
    public var cancellationInstructions: String
    public var notes: String

    public init(mode: Mode = .create, now: Date = .now, locale: Locale = .current) {
        self.mode = mode
        switch mode {
        case .create:
            merchantName = ""
            planName = ""
            amount = nil
            currencyCode = locale.currency?.identifier.uppercased() ?? "USD"
            frequency = .monthly
            customCount = 1
            customUnit = .month
            category = .other
            status = .active
            ownership = .personal
            hasNextBillingDate = true
            nextBillingDate = now
            hasStartDate = false
            startDate = now
            hasTrialEnd = false
            trialEndDate = now
            hasIntroPricing = false
            regularPrice = nil
            introEndDate = now
            paymentMethodLabel = ""
            websiteURLText = ""
            cancellationURLText = ""
            cancellationInstructions = ""
            notes = ""
        case .edit(let subscription):
            merchantName = subscription.merchantName
            planName = subscription.planName ?? ""
            amount = subscription.amount
            currencyCode = subscription.currencyCode
            frequency = subscription.billingFrequency
            customCount = subscription.customInterval?.count ?? 1
            customUnit = subscription.customInterval?.unit ?? .month
            category = subscription.category
            status = subscription.status
            ownership = subscription.ownershipType
            hasNextBillingDate = subscription.nextBillingDate != nil
            nextBillingDate = subscription.nextBillingDate ?? now
            hasStartDate = subscription.startDate != nil
            startDate = subscription.startDate ?? now
            hasTrialEnd = subscription.trialEndDate != nil
            trialEndDate = subscription.trialEndDate ?? now
            hasIntroPricing = subscription.regularPrice != nil
                && subscription.introductoryPriceEndDate != nil
            regularPrice = subscription.regularPrice
            introEndDate = subscription.introductoryPriceEndDate ?? now
            paymentMethodLabel = subscription.paymentMethodLabel ?? ""
            websiteURLText = subscription.websiteURL?.absoluteString ?? ""
            cancellationURLText = subscription.cancellationURL?.absoluteString ?? ""
            cancellationInstructions = subscription.cancellationInstructions ?? ""
            notes = subscription.notes ?? ""
        }
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Validation

    public var validationError: ValidationError? {
        if trimmed(merchantName).isEmpty { return .missingMerchant }
        guard let amount else { return .missingAmount }
        if amount <= 0 { return .nonPositiveAmount }
        if frequency == .custom, customCount < 1 { return .invalidCustomInterval }
        if hasIntroPricing, (regularPrice ?? 0) <= 0 { return .missingIntroductoryPrice }
        if !trimmed(websiteURLText).isEmpty, parseHTTPURL(websiteURLText) == nil {
            return .invalidWebsiteURL
        }
        if !trimmed(cancellationURLText).isEmpty, parseHTTPURL(cancellationURLText) == nil {
            return .invalidCancellationURL
        }
        return nil
    }

    public var canSave: Bool { validationError == nil }

    /// Only http/https URLs are accepted — javascript:/data: and friends are
    /// rejected at entry (privacy model, hard rule 3/4).
    func parseHTTPURL(_ text: String) -> URL? {
        let candidate = trimmed(text)
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }

    /// Default reminders for a new entry, from the user's notification
    /// preferences: one renewal reminder at the default lead time, and the
    /// trial defaults (typically 7 + 1 days) when a trial end is set.
    /// All editable per-entry afterwards.
    public func defaultReminderRules(preferences: NotificationPreferences = .load()) -> [ReminderRule] {
        var rules: [ReminderRule] = []
        if hasNextBillingDate {
            rules.append(ReminderRule(
                reminderType: preferences.defaultLeadDays == 0 ? .billingDay : .beforeBilling,
                leadTimeDays: preferences.defaultLeadDays,
                timeOfDayMinutes: preferences.defaultTimeOfDayMinutes
            ))
        }
        if hasTrialEnd {
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

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ text: String) -> String? {
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    // MARK: - Persistence

    /// Validates and persists. Creates a new subscription or applies edits to
    /// the existing one, always through the repository seam.
    public func save(using repository: any SubscriptionRepository) throws {
        if let validationError { throw validationError }
        guard let amount else { throw ValidationError.missingAmount }

        let interval = frequency == .custom
            ? CustomInterval(count: customCount, unit: customUnit)
            : nil

        switch mode {
        case .create:
            let subscription = Subscription(
                merchantName: trimmed(merchantName),
                planName: nonEmpty(planName),
                amount: amount,
                currencyCode: currencyCode,
                billingFrequency: frequency,
                customInterval: interval,
                status: status,
                startDate: hasStartDate ? startDate : nil,
                trialEndDate: hasTrialEnd ? trialEndDate : nil,
                nextBillingDate: hasNextBillingDate ? nextBillingDate : nil,
                introductoryPrice: hasIntroPricing ? amount : nil,
                regularPrice: hasIntroPricing ? regularPrice : nil,
                introductoryPriceEndDate: hasIntroPricing ? introEndDate : nil,
                category: category,
                paymentMethodLabel: nonEmpty(paymentMethodLabel),
                ownershipType: ownership,
                websiteURL: parseHTTPURL(websiteURLText),
                cancellationURL: parseHTTPURL(cancellationURLText),
                cancellationInstructions: nonEmpty(cancellationInstructions),
                notes: nonEmpty(notes),
                detectionSource: .manual
            )
            subscription.reminderRules = defaultReminderRules()
            try repository.insert(subscription)

        case .edit(let subscription):
            subscription.update(merchantName: trimmed(merchantName))
            subscription.planName = nonEmpty(planName)
            subscription.amount = amount
            subscription.currencyCode = currencyCode.uppercased()
            subscription.billingFrequency = frequency
            subscription.customInterval = interval
            subscription.status = status
            subscription.startDate = hasStartDate ? startDate : nil
            subscription.trialEndDate = hasTrialEnd ? trialEndDate : nil
            subscription.nextBillingDate = hasNextBillingDate ? nextBillingDate : nil
            subscription.introductoryPrice = hasIntroPricing ? amount : nil
            subscription.regularPrice = hasIntroPricing ? regularPrice : nil
            subscription.introductoryPriceEndDate = hasIntroPricing ? introEndDate : nil
            subscription.category = category
            subscription.paymentMethodLabel = nonEmpty(paymentMethodLabel)
            subscription.ownershipType = ownership
            subscription.websiteURL = parseHTTPURL(websiteURLText)
            subscription.cancellationURL = parseHTTPURL(cancellationURLText)
            subscription.cancellationInstructions = nonEmpty(cancellationInstructions)
            subscription.notes = nonEmpty(notes)
            subscription.updatedAt = .now
            try repository.save()
        }
    }
}
