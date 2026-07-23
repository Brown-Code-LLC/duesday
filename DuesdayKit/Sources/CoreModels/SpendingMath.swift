import Foundation

/// Frequency normalization and currency-safe aggregation.
///
/// Normalized values are *estimates* and must be labeled as such in UI (spec:
/// spending calculations). Amounts in different currencies are never summed —
/// aggregation only exists per currency code.
public enum SpendingMath {
    /// A per-currency total. The only aggregate shape the app exposes.
    public struct CurrencyTotal: Hashable, Sendable {
        public let currencyCode: String
        public let total: Decimal

        public init(currencyCode: String, total: Decimal) {
            self.currencyCode = currencyCode
            self.total = total
        }

        public var money: Money { Money(amount: total, currencyCode: currencyCode) }
    }

    private static let daysPerYear = Decimal(36525) / Decimal(100) // 365.25
    private static let weeksPerYear = Decimal(52)
    private static let monthsPerYear = Decimal(12)

    /// Billing occurrences per year, or nil when the frequency is `.custom`
    /// without a valid interval (unknown — never guessed).
    public static func occurrencesPerYear(
        frequency: BillingFrequency,
        customInterval: CustomInterval? = nil
    ) -> Decimal? {
        switch frequency {
        case .weekly: weeksPerYear
        case .monthly: monthsPerYear
        case .quarterly: Decimal(4)
        case .semiannual: Decimal(2)
        case .annual: Decimal(1)
        case .custom:
            customInterval.flatMap { interval in
                guard interval.count >= 1 else { return nil }
                let count = Decimal(interval.count)
                return switch interval.unit {
                case .day: daysPerYear / count
                case .week: weeksPerYear / count
                case .month: monthsPerYear / count
                case .year: Decimal(1) / count
                }
            }
        }
    }

    /// Estimated monthly cost. Spec rules: weekly ×52 ÷12, monthly ×1,
    /// quarterly ÷3, semiannual ÷6, annual ÷12, custom from its interval —
    /// all equivalent to occurrences/year ÷ 12.
    public static func monthlyEstimate(
        amount: Decimal,
        frequency: BillingFrequency,
        customInterval: CustomInterval? = nil
    ) -> Decimal? {
        occurrencesPerYear(frequency: frequency, customInterval: customInterval)
            .map { (amount * $0 / monthsPerYear).rounded(scale: 2) }
    }

    /// Estimated annualized cost: occurrences/year × amount.
    public static func annualEstimate(
        amount: Decimal,
        frequency: BillingFrequency,
        customInterval: CustomInterval? = nil
    ) -> Decimal? {
        occurrencesPerYear(frequency: frequency, customInterval: customInterval)
            .map { (amount * $0).rounded(scale: 2) }
    }

    /// Groups amounts by currency and sums within each group. Result is sorted
    /// by descending total count significance: largest group first, then code.
    public static func totalsByCurrency(_ amounts: [Money]) -> [CurrencyTotal] {
        let grouped = Dictionary(grouping: amounts, by: \.currencyCode)
        return grouped
            .map { code, values in
                CurrencyTotal(
                    currencyCode: code,
                    total: values.reduce(Decimal.zero) { $0 + $1.amount }.rounded(scale: 2)
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.currencyCode < rhs.currencyCode
            }
    }
}
