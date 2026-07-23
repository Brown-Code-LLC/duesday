import Foundation

/// Projects upcoming charges for a set of subscriptions. Subscriptions whose
/// schedule is unknown (no next-billing anchor or invalid custom interval) are
/// skipped — never guessed (spec: detection pipeline / spending calculations).
public enum UpcomingCharges {
    public struct Charge {
        public let date: Date
        public let subscription: Subscription

        public var money: Money { subscription.money }
    }

    /// All projected charges inside `interval`, soonest first. Only statuses
    /// that count toward spending are included; archived subscriptions never are.
    public static func charges(
        for subscriptions: [Subscription],
        within interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Charge] {
        subscriptions
            .filter { !$0.isArchived && $0.status.countsTowardSpending }
            .flatMap { subscription -> [Charge] in
                guard let anchor = subscription.nextBillingDate else { return [] }
                return BillingSchedule.occurrences(
                    in: interval,
                    anchor: anchor,
                    frequency: subscription.billingFrequency,
                    customInterval: subscription.customInterval,
                    calendar: calendar
                )
                .map { Charge(date: $0, subscription: subscription) }
            }
            .sorted { $0.date < $1.date }
    }

    /// Per-currency totals of projected charges inside `interval`.
    /// Currencies are never merged (spec: spending calculations).
    public static func totals(
        for subscriptions: [Subscription],
        within interval: DateInterval,
        calendar: Calendar = .current
    ) -> [SpendingMath.CurrencyTotal] {
        SpendingMath.totalsByCurrency(
            charges(for: subscriptions, within: interval, calendar: calendar).map(\.money)
        )
    }

    /// Convenience window starting now.
    public static func window(days: Int, from start: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
