import CoreModels
import FeatureSubscriptions
import Foundation
import Persistence
import Testing

/// Records repository calls so form-model persistence is verified without SwiftData.
@MainActor
private final class MockSubscriptionRepository: SubscriptionRepository {
    var inserted: [Subscription] = []
    var saveCallCount = 0

    func fetchAll(includeArchived: Bool) throws -> [Subscription] { inserted }
    func fetch(id: UUID) throws -> Subscription? { inserted.first { $0.id == id } }
    func fetchByNormalizedMerchant(_ normalizedName: String) throws -> [Subscription] {
        inserted.filter { $0.normalizedMerchantName == normalizedName }
    }
    func insert(_ subscription: Subscription) throws { inserted.append(subscription) }
    func delete(_ subscription: Subscription) throws { inserted.removeAll { $0.id == subscription.id } }
    func archive(_ subscription: Subscription) throws { subscription.archivedAt = .now }
    func unarchive(_ subscription: Subscription) throws { subscription.archivedAt = nil }
    func save() throws { saveCallCount += 1 }
}

@Suite("Subscription form validation")
@MainActor
struct SubscriptionFormModelTests {
    private func validModel() -> SubscriptionFormModel {
        let model = SubscriptionFormModel(mode: .create)
        model.merchantName = "Netflix"
        model.amount = Decimal(string: "7.99")
        return model
    }

    @Test("Empty form reports missing merchant first")
    func missingMerchant() {
        let model = SubscriptionFormModel(mode: .create)
        #expect(model.validationError == .missingMerchant)
        #expect(!model.canSave)
    }

    @Test("Merchant without amount reports missing amount")
    func missingAmount() {
        let model = SubscriptionFormModel(mode: .create)
        model.merchantName = "Netflix"
        #expect(model.validationError == .missingAmount)
    }

    @Test("Zero and negative amounts are rejected")
    func nonPositiveAmount() {
        let model = validModel()
        model.amount = 0
        #expect(model.validationError == .nonPositiveAmount)
        model.amount = -5
        #expect(model.validationError == .nonPositiveAmount)
    }

    @Test("Valid model has no validation error")
    func validState() {
        #expect(validModel().validationError == nil)
    }

    @Test("Non-http(s) links are rejected — including javascript:")
    func unsafeLinks() {
        let model = validModel()
        model.cancellationURLText = "javascript:alert(1)"
        #expect(model.validationError == .invalidCancellationURL)
        model.cancellationURLText = "ftp://example.com"
        #expect(model.validationError == .invalidCancellationURL)
        model.cancellationURLText = "https://netflix.com/cancel"
        #expect(model.validationError == nil)
    }

    @Test("Saving creates a subscription through the repository")
    func createSaves() throws {
        let repository = MockSubscriptionRepository()
        let model = validModel()
        model.planName = "  Standard  "
        model.frequency = .annual
        model.category = .streaming
        try model.save(using: repository)

        #expect(repository.inserted.count == 1)
        let saved = try #require(repository.inserted.first)
        #expect(saved.merchantName == "Netflix")
        #expect(saved.planName == "Standard")
        #expect(saved.billingFrequency == .annual)
        #expect(saved.category == .streaming)
        #expect(saved.detectionSource == .manual)
        #expect(saved.customInterval == nil)
    }

    @Test("Custom frequency persists its interval; others drop it")
    func customIntervalHandling() throws {
        let repository = MockSubscriptionRepository()
        let model = validModel()
        model.frequency = .custom
        model.customCount = 2
        model.customUnit = .week
        try model.save(using: repository)

        let saved = try #require(repository.inserted.first)
        #expect(saved.customInterval == CustomInterval(count: 2, unit: .week))
    }

    @Test("Saving an invalid form throws and persists nothing")
    func invalidSaveThrows() {
        let repository = MockSubscriptionRepository()
        let model = SubscriptionFormModel(mode: .create)
        #expect(throws: SubscriptionFormModel.ValidationError.missingMerchant) {
            try model.save(using: repository)
        }
        #expect(repository.inserted.isEmpty)
    }

    @Test("New subscriptions get default reminder rules from preferences")
    func defaultRules() {
        let model = validModel()
        model.hasNextBillingDate = true
        model.hasTrialEnd = true

        // Deterministic preferences (not whatever is in UserDefaults).
        let preferences = NotificationPreferences(
            defaultLeadDays: 3,
            trialLeadDays: [7, 1]
        )
        let rules = model.defaultReminderRules(preferences: preferences)

        let renewalRules = rules.filter { $0.reminderType == .beforeBilling && $0.leadTimeDays == 3 }
        let trialRules = rules.filter { $0.reminderType == .trialEnd }
        let leadDays: [Int] = rules.map { $0.leadTimeDays }.sorted()
        #expect(renewalRules.count == 1)
        #expect(trialRules.count == 2)
        #expect(leadDays == [1, 3, 7])
    }

    @Test("A day-of default becomes a billing-day rule")
    func dayOfDefault() {
        let model = validModel()
        model.hasNextBillingDate = true
        let preferences = NotificationPreferences(defaultLeadDays: 0)
        let rules = model.defaultReminderRules(preferences: preferences)
        #expect(rules.count == 1)
        #expect(rules.first?.reminderType == .billingDay)
    }

    @Test("No billing date means no billing reminders are created")
    func noDatesNoRules() throws {
        let repository = MockSubscriptionRepository()
        let model = validModel()
        model.hasNextBillingDate = false
        model.hasTrialEnd = false
        try model.save(using: repository)

        let saved = try #require(repository.inserted.first)
        #expect(saved.reminderRules.isEmpty)
    }

    @Test("Edit mode applies changes to the existing subscription")
    func editApplies() throws {
        let existing = Subscription(
            merchantName: "Netflix",
            amount: Decimal(string: "7.99") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly
        )
        let repository = MockSubscriptionRepository()
        let model = SubscriptionFormModel(mode: .edit(existing))
        model.merchantName = "Netflix Premium"
        model.amount = Decimal(string: "22.99")
        model.frequency = .monthly
        try model.save(using: repository)

        #expect(repository.inserted.isEmpty)
        #expect(repository.saveCallCount == 1)
        #expect(existing.merchantName == "Netflix Premium")
        #expect(existing.normalizedMerchantName == "netflix premium")
        #expect(existing.amount == Decimal(string: "22.99"))
    }
}
