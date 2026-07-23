import CoreModels
import Foundation
import SwiftData

/// Deterministic sample data for previews, UI tests, and the DEBUG-only
/// `-duesday-sample-data` launch mode. Never referenced from a release code
/// path (ADR-9): the seeding entry points only exist to be called from
/// preview/test/DEBUG contexts, and sample stores are always in-memory.
///
/// The set intentionally exercises every screen state: upcoming renewals,
/// a converting trial, an introductory price about to rise, a failed payment,
/// recorded price history, a second currency, and a canceled entry.
public enum SampleData {
    /// Fixed reference date so previews and snapshot tests are stable.
    public static let referenceDate = ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z") ?? .now

    public static func subscriptions(now: Date = referenceDate) -> [Subscription] {
        let calendar = Calendar.current

        func days(_ n: Int) -> Date {
            calendar.date(byAdding: .day, value: n, to: now) ?? now
        }
        func months(_ n: Int) -> Date {
            calendar.date(byAdding: .month, value: n, to: now) ?? now
        }

        // Streaming — upcoming renewal with recorded price history.
        let netflix = Subscription(
            merchantName: "Netflix",
            planName: "Standard, 1080p",
            amount: Decimal(string: "15.49") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            startDate: months(-40),
            nextBillingDate: days(5),
            lastBillingDate: days(-25),
            category: .streaming,
            paymentMethodLabel: "Visa ···4821",
            websiteURL: URL(string: "https://www.netflix.com"),
            cancellationURL: URL(string: "https://www.netflix.com/cancelplan"),
            cancellationInstructions: "Go to netflix.com/account › Membership › Cancel. Takes effect at the end of the paid period.",
            createdAt: months(-6)
        )
        let historyAmounts: [(monthsAgo: Int, amount: String)] = [
            (-30, "13.99"), (-24, "13.99"), (-18, "14.99"),
            (-12, "14.99"), (-6, "14.99"), (-1, "15.49"),
        ]
        netflix.renewalEvents = historyAmounts.map { entry in
            RenewalEvent(
                expectedDate: months(entry.monthsAgo),
                expectedAmount: Decimal(string: entry.amount),
                actualDate: months(entry.monthsAgo),
                actualAmount: Decimal(string: entry.amount),
                status: .confirmed
            )
        }

        // Music — introductory price rising next month.
        let spotify = Subscription(
            merchantName: "Spotify",
            planName: "Duo",
            amount: Decimal(string: "10.99") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            startDate: months(-20),
            nextBillingDate: days(16),
            introductoryPrice: Decimal(string: "10.99"),
            regularPrice: Decimal(string: "11.99"),
            introductoryPriceEndDate: days(16),
            category: .music,
            ownershipType: .shared,
            createdAt: months(-5)
        )

        // Second music service — overlap suggestion in Insights.
        let youtube = Subscription(
            merchantName: "YouTube Premium",
            amount: Decimal(string: "13.99") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(9),
            category: .music,
            createdAt: months(-4)
        )

        // Streaming trial converting soon.
        let paramount = Subscription(
            merchantName: "Paramount+",
            amount: Decimal(string: "0") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .trial,
            startDate: days(-20),
            trialEndDate: days(10),
            nextBillingDate: days(10),
            regularPrice: Decimal(string: "11.99"),
            category: .streaming,
            createdAt: days(-20)
        )

        // Utilities — variable-style monthly bill.
        let conEdison = Subscription(
            merchantName: "Con Edison",
            planName: "Electric",
            amount: Decimal(string: "96.40") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(12),
            category: .utilities,
            notes: "Amount varies with usage; this is last month's bill.",
            createdAt: months(-8)
        )

        // Family phone plan.
        let verizon = Subscription(
            merchantName: "Verizon",
            planName: "Wireless",
            amount: Decimal(string: "82.00") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(26),
            category: .utilities,
            ownershipType: .family,
            createdAt: months(-10)
        )

        // Work software with a recent failed payment.
        let adobe = Subscription(
            merchantName: "Adobe Creative Cloud",
            amount: Decimal(string: "59.99") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(22),
            category: .software,
            paymentMethodLabel: "Amex ···1005",
            ownershipType: .business,
            createdAt: months(-14)
        )
        adobe.renewalEvents = [
            RenewalEvent(
                expectedDate: days(-8),
                expectedAmount: Decimal(string: "59.99"),
                actualDate: days(-8),
                status: .failed
            )
        ]

        // Recent renewal for the Lately feed.
        let audible = Subscription(
            merchantName: "Audible",
            amount: Decimal(string: "14.95") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(25),
            lastBillingDate: days(-5),
            category: .shopping,
            createdAt: months(-9)
        )
        audible.renewalEvents = [
            RenewalEvent(
                expectedDate: days(-5),
                expectedAmount: Decimal(string: "14.95"),
                actualDate: days(-5),
                actualAmount: Decimal(string: "14.95"),
                status: .confirmed
            )
        ]

        // Recently added — shows in Lately.
        let squarespace = Subscription(
            merchantName: "Squarespace",
            planName: "Personal",
            amount: Decimal(string: "23.00") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(29),
            category: .productivity,
            createdAt: days(-2)
        )

        // Second currency — held separately everywhere.
        let leMonde = Subscription(
            merchantName: "Le Monde",
            planName: "Abonnement numérique",
            amount: Decimal(string: "11.99") ?? 0,
            currencyCode: "EUR",
            billingFrequency: .monthly,
            status: .active,
            nextBillingDate: days(18),
            category: .news,
            createdAt: months(-3)
        )

        // Annual entry for cadence variety.
        let nyt = Subscription(
            merchantName: "The New York Times",
            planName: "All Access",
            amount: Decimal(string: "144.00") ?? 0,
            currencyCode: "USD",
            billingFrequency: .annual,
            status: .active,
            startDate: months(-2),
            nextBillingDate: months(10),
            category: .news,
            createdAt: months(-2)
        )

        // Canceled (not archived) — appears under the Cancelled filter.
        let equinox = Subscription(
            merchantName: "Equinox",
            amount: Decimal(string: "185.00") ?? 0,
            currencyCode: "USD",
            billingFrequency: .monthly,
            status: .canceled,
            startDate: months(-24),
            lastBillingDate: days(-40),
            category: .fitness,
            createdAt: months(-24)
        )

        return [
            netflix, spotify, youtube, paramount, conEdison, verizon,
            adobe, audible, squarespace, leMonde, nyt, equinox,
        ]
    }

    /// Inserts the sample set into an (in-memory) context. Idempotent per
    /// context: skips when subscriptions already exist.
    public static func seed(into context: ModelContext) throws {
        var descriptor = FetchDescriptor<Subscription>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }

        for subscription in subscriptions() {
            context.insert(subscription)
        }
        try context.save()
    }
}
