import CoreModels
import Foundation
import Testing

@Suite("Frequency normalization")
struct FrequencyNormalizationTests {
    @Test("Monthly amount passes through unchanged")
    func monthly() {
        #expect(SpendingMath.monthlyEstimate(amount: 15, frequency: .monthly) == 15)
    }

    @Test("Weekly normalizes as ×52 ÷ 12")
    func weekly() {
        let result = SpendingMath.monthlyEstimate(amount: 12, frequency: .weekly)
        #expect(result == (Decimal(12) * 52 / 12).rounded(scale: 2))
        #expect(result == Decimal(52))
    }

    @Test("Quarterly divides by 3")
    func quarterly() {
        #expect(SpendingMath.monthlyEstimate(amount: 30, frequency: .quarterly) == 10)
    }

    @Test("Semiannual divides by 6")
    func semiannual() {
        #expect(SpendingMath.monthlyEstimate(amount: 60, frequency: .semiannual) == 10)
    }

    @Test("Annual divides by 12")
    func annual() {
        #expect(SpendingMath.monthlyEstimate(amount: 120, frequency: .annual) == 10)
    }

    @Test("Custom every-2-weeks yields 26 occurrences per year")
    func customBiweekly() {
        let interval = CustomInterval(count: 2, unit: .week)
        #expect(SpendingMath.occurrencesPerYear(frequency: .custom, customInterval: interval) == 26)
        let monthly = SpendingMath.monthlyEstimate(amount: 6, frequency: .custom, customInterval: interval)
        #expect(monthly == (Decimal(6) * 26 / 12).rounded(scale: 2))
    }

    @Test("Custom every-3-months matches quarterly")
    func customQuarterly() {
        let interval = CustomInterval(count: 3, unit: .month)
        #expect(
            SpendingMath.monthlyEstimate(amount: 30, frequency: .custom, customInterval: interval)
                == SpendingMath.monthlyEstimate(amount: 30, frequency: .quarterly)
        )
    }

    @Test("Custom without an interval is unknown, never guessed")
    func customMissingInterval() {
        #expect(SpendingMath.monthlyEstimate(amount: 10, frequency: .custom) == nil)
        #expect(SpendingMath.annualEstimate(amount: 10, frequency: .custom) == nil)
        #expect(SpendingMath.occurrencesPerYear(frequency: .custom) == nil)
    }

    @Test("Annual estimate is occurrences × amount")
    func annualEstimate() {
        #expect(SpendingMath.annualEstimate(amount: 10, frequency: .monthly) == 120)
        #expect(SpendingMath.annualEstimate(amount: 12, frequency: .weekly) == 624)
    }
}

@Suite("Currency aggregation")
struct CurrencyAggregationTests {
    @Test("Different currencies are never summed together")
    func currenciesStaySeparate() {
        let totals = SpendingMath.totalsByCurrency([
            Money(amount: 10, currencyCode: "USD"),
            Money(amount: 5, currencyCode: "EUR"),
            Money(amount: 7, currencyCode: "USD"),
        ])
        #expect(totals.count == 2)
        #expect(totals.first(where: { $0.currencyCode == "USD" })?.total == 17)
        #expect(totals.first(where: { $0.currencyCode == "EUR" })?.total == 5)
    }

    @Test("Largest total sorts first, ties break by code")
    func sorting() {
        let totals = SpendingMath.totalsByCurrency([
            Money(amount: 5, currencyCode: "EUR"),
            Money(amount: 20, currencyCode: "GBP"),
            Money(amount: 5, currencyCode: "CHF"),
        ])
        #expect(totals.map(\.currencyCode) == ["GBP", "CHF", "EUR"])
    }

    @Test("Empty input produces no totals")
    func empty() {
        #expect(SpendingMath.totalsByCurrency([]).isEmpty)
    }

    @Test("Currency codes are case-normalized")
    func caseNormalization() {
        let totals = SpendingMath.totalsByCurrency([
            Money(amount: 1, currencyCode: "usd"),
            Money(amount: 2, currencyCode: "USD"),
        ])
        #expect(totals.count == 1)
        #expect(totals.first?.total == 3)
    }
}

@Suite("Money")
struct MoneyTests {
    @Test("Decimal rounding uses banker's rounding at 2 places")
    func rounding() {
        #expect((Decimal(string: "10.005") ?? 0).rounded(scale: 2) == Decimal(string: "10.00"))
        #expect((Decimal(string: "10.015") ?? 0).rounded(scale: 2) == Decimal(string: "10.02"))
        #expect((Decimal(string: "10.999") ?? 0).rounded(scale: 2) == Decimal(string: "11.00"))
    }

    @Test("Formatting respects an explicit locale")
    func formatting() {
        let money = Money(amount: Decimal(string: "15.99") ?? 0, currencyCode: "USD")
        #expect(money.formatted(locale: Locale(identifier: "en_US")) == "$15.99")
    }
}
