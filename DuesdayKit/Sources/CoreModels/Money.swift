import Foundation

/// A monetary value paired with its ISO-4217 currency code.
/// Money is always `Decimal` — never floating point (spec: core data models).
public struct Money: Hashable, Sendable, Codable {
    public var amount: Decimal
    public var currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
    }

    /// Localized currency string, e.g. "$15.99" / "15,99 €".
    public func formatted(locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}

extension Decimal {
    /// Banker's-rounds to `scale` fraction digits. Used at display/aggregation
    /// boundaries; intermediate math keeps full precision.
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
