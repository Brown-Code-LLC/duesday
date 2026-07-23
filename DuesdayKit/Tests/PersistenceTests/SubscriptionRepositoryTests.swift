import CoreModels
import Foundation
import Persistence
import SwiftData
import Testing
import TestingSupport

@Suite("Subscription repository")
@MainActor
struct SubscriptionRepositoryTests {
    /// Holds the controller alongside the repository — the ModelContainer must
    /// outlive every context operation or SwiftData traps on a dead context.
    private struct Fixture {
        let controller: PersistenceController
        let repository: SwiftDataSubscriptionRepository

        init() throws {
            controller = try PersistenceController(inMemory: true)
            repository = SwiftDataSubscriptionRepository(context: controller.mainContext)
        }
    }

    private func makeSubscription(merchant: String = "Netflix") -> Subscription {
        Subscription(
            merchantName: merchant,
            amount: Decimal(string: "7.99") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly
        )
    }

    @Test("Insert then fetch round-trips")
    func insertAndFetch() throws {
        let fixture = try Fixture()
        let subscription = makeSubscription()
        try fixture.repository.insert(subscription)

        let fetched = try fixture.repository.fetch(id: subscription.id)
        #expect(fetched?.merchantName == "Netflix")
        #expect(fetched?.amount == Decimal(string: "7.99"))
        #expect(fetched?.currencyCode == "USD")
    }

    @Test("Archive hides from default fetch, unarchive restores")
    func archiveLifecycle() throws {
        let fixture = try Fixture()
        let subscription = makeSubscription()
        try fixture.repository.insert(subscription)

        try fixture.repository.archive(subscription)
        #expect(try fixture.repository.fetchAll(includeArchived: false).isEmpty)
        #expect(try fixture.repository.fetchAll(includeArchived: true).count == 1)
        #expect(subscription.archivedAt != nil)

        try fixture.repository.unarchive(subscription)
        #expect(try fixture.repository.fetchAll(includeArchived: false).count == 1)
        #expect(subscription.archivedAt == nil)
    }

    @Test("Delete removes the subscription")
    func delete() throws {
        let fixture = try Fixture()
        let subscription = makeSubscription()
        try fixture.repository.insert(subscription)
        try fixture.repository.delete(subscription)
        #expect(try fixture.repository.fetchAll(includeArchived: true).isEmpty)
    }

    @Test("Normalized merchant lookup matches across naming variants")
    func duplicateLookup() throws {
        let fixture = try Fixture()
        try fixture.repository.insert(makeSubscription(merchant: "Netflix, Inc."))

        let matches = try fixture.repository.fetchByNormalizedMerchant(
            MerchantNormalizer.normalize("NETFLIX Inc")
        )
        #expect(matches.count == 1)
    }

    @Test("Cascade delete removes renewal events and reminder rules")
    func cascadeDelete() throws {
        let fixture = try Fixture()
        let subscription = makeSubscription()
        try fixture.repository.insert(subscription)

        let renewal = RenewalEvent(expectedDate: .now)
        let rule = ReminderRule(reminderType: .beforeBilling, leadTimeDays: 3)
        subscription.renewalEvents.append(renewal)
        subscription.reminderRules.append(rule)
        try fixture.repository.save()

        try fixture.repository.delete(subscription)

        let renewals = try fixture.controller.mainContext.fetch(FetchDescriptor<RenewalEvent>())
        let rules = try fixture.controller.mainContext.fetch(FetchDescriptor<ReminderRule>())
        #expect(renewals.isEmpty)
        #expect(rules.isEmpty)
    }
}

@Suite("Sample data")
@MainActor
struct SampleDataTests {
    @Test("Seeding is idempotent per store")
    func idempotentSeed() throws {
        let controller = try PersistenceController(inMemory: true)
        try SampleData.seed(into: controller.mainContext)
        try SampleData.seed(into: controller.mainContext)

        let count = try controller.mainContext.fetchCount(FetchDescriptor<Subscription>())
        #expect(count == SampleData.subscriptions().count)
    }
}

@Suite("Upcoming charges")
@MainActor
struct UpcomingChargesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    @Test("Charges include repeats inside the window and stay currency-separated")
    func projectionAndTotals() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext

        let weekly = Subscription(
            merchantName: "WeeklyBox",
            amount: 5,
            currencyCode: "USD",
            billingFrequency: .weekly,
            nextBillingDate: date(2026, 7, 22)
        )
        let euro = Subscription(
            merchantName: "Le Monde",
            amount: 12,
            currencyCode: "EUR",
            billingFrequency: .monthly,
            nextBillingDate: date(2026, 7, 25)
        )
        let outside = Subscription(
            merchantName: "Later",
            amount: 99,
            currencyCode: "USD",
            billingFrequency: .monthly,
            nextBillingDate: date(2026, 9, 1)
        )
        let canceled = Subscription(
            merchantName: "Gone",
            amount: 50,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .canceled,
            nextBillingDate: date(2026, 7, 23)
        )
        for subscription in [weekly, euro, outside, canceled] {
            context.insert(subscription)
        }
        try context.save()

        // Container must stay alive while model properties are read.
        withExtendedLifetime(controller) {
            let window = DateInterval(start: date(2026, 7, 20), end: date(2026, 8, 3))
            let totals = UpcomingCharges.totals(
                for: [weekly, euro, outside, canceled],
                within: window,
                calendar: calendar
            )

            // WeeklyBox bills Jul 22 and Jul 29 → 10 USD. Canceled and
            // out-of-window subscriptions contribute nothing.
            #expect(totals.count == 2)
            #expect(totals.first(where: { $0.currencyCode == "USD" })?.total == 10)
            #expect(totals.first(where: { $0.currencyCode == "EUR" })?.total == 12)
        }
    }

    @Test("Subscriptions without a next billing date are skipped, never guessed")
    func unknownAnchorSkipped() throws {
        let controller = try PersistenceController(inMemory: true)
        let subscription = Subscription(
            merchantName: "Mystery",
            amount: 10,
            currencyCode: "USD",
            billingFrequency: .monthly
        )
        controller.mainContext.insert(subscription)
        try controller.mainContext.save()

        withExtendedLifetime(controller) {
            let window = DateInterval(start: date(2026, 7, 1), end: date(2026, 12, 31))
            let charges = UpcomingCharges.charges(for: [subscription], within: window, calendar: calendar)
            #expect(charges.isEmpty)
        }
    }
}
