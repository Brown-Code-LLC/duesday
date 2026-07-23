import CoreModels
import Foundation
import Testing

@Suite("Billing schedule projection")
struct BillingScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let value = calendar.date(from: components) else {
            Issue.record("Could not build date \(year)-\(month)-\(day)")
            return .distantPast
        }
        return value
    }

    @Test("Anchor in the future is returned as-is")
    func futureAnchor() {
        let anchor = date(2026, 9, 1)
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 7, 20),
            anchor: anchor,
            frequency: .monthly,
            calendar: calendar
        )
        #expect(next == anchor)
    }

    @Test("Monthly from Jan 31 clamps to end of February")
    func monthEndClamping() {
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 2, 10),
            anchor: date(2026, 1, 31),
            frequency: .monthly,
            calendar: calendar
        )
        #expect(next == date(2026, 2, 28))
    }

    @Test("Jan 31 anchor does not permanently drift after February")
    func noPermanentDrift() {
        // Projection is anchor + k×step, so March recovers the 31st.
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 3, 1),
            anchor: date(2026, 1, 31),
            frequency: .monthly,
            calendar: calendar
        )
        #expect(next == date(2026, 3, 31))
    }

    @Test("Weekly projection crosses the US DST boundary keeping wall-clock time")
    func weeklyAcrossDST() {
        // US DST springs forward 2026-03-08.
        let anchor = date(2026, 3, 3)
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 3, 9),
            anchor: anchor,
            frequency: .weekly,
            calendar: calendar
        )
        #expect(next == date(2026, 3, 10))
        let hour = calendar.component(.hour, from: next ?? .distantPast)
        #expect(hour == 12)
    }

    @Test("Custom every-2-weeks steps 14 days")
    func customInterval() {
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 7, 2),
            anchor: date(2026, 7, 1),
            frequency: .custom,
            customInterval: CustomInterval(count: 2, unit: .week),
            calendar: calendar
        )
        #expect(next == date(2026, 7, 15))
    }

    @Test("Custom frequency without an interval projects nothing")
    func customWithoutInterval() {
        let next = BillingSchedule.nextDate(
            onOrAfter: date(2026, 7, 2),
            anchor: date(2026, 7, 1),
            frequency: .custom,
            customInterval: nil,
            calendar: calendar
        )
        #expect(next == nil)
    }

    @Test("Occurrences inside a window are complete, ordered, and bounded")
    func occurrencesInWindow() {
        let window = DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1))
        let occurrences = BillingSchedule.occurrences(
            in: window,
            anchor: date(2026, 6, 3),
            frequency: .weekly,
            calendar: calendar
        )
        #expect(occurrences == [
            date(2026, 7, 1), date(2026, 7, 8), date(2026, 7, 15),
            date(2026, 7, 22), date(2026, 7, 29),
        ])
    }

    @Test("Window end is exclusive")
    func windowEndExclusive() {
        let window = DateInterval(start: date(2026, 7, 1), end: date(2026, 8, 1))
        let occurrences = BillingSchedule.occurrences(
            in: window,
            anchor: date(2026, 8, 1),
            frequency: .monthly,
            calendar: calendar
        )
        #expect(occurrences.isEmpty)
    }

    @Test("Annual occurrence lands inside a multi-year window once per year")
    func annualOccurrences() {
        let window = DateInterval(start: date(2026, 1, 1), end: date(2029, 1, 1))
        let occurrences = BillingSchedule.occurrences(
            in: window,
            anchor: date(2026, 2, 14),
            frequency: .annual,
            calendar: calendar
        )
        #expect(occurrences == [date(2026, 2, 14), date(2027, 2, 14), date(2028, 2, 14)])
    }
}

@Suite("Merchant normalization")
struct MerchantNormalizerTests {
    @Test("Legal suffixes and punctuation are stripped")
    func suffixStripping() {
        #expect(MerchantNormalizer.normalize("Netflix, Inc.") == "netflix")
        #expect(MerchantNormalizer.normalize("NETFLIX Inc") == "netflix")
        #expect(MerchantNormalizer.normalize("Spotify AB") == "spotify ab")
    }

    @Test("Diacritics fold for matching")
    func diacritics() {
        #expect(MerchantNormalizer.normalize("Café Média SARL") == "cafe media")
    }

    @Test("A name that is only a suffix is preserved")
    func suffixOnlyName() {
        #expect(MerchantNormalizer.normalize("Inc") == "inc")
    }

    @Test("Multi-word merchants collapse whitespace")
    func whitespace() {
        #expect(MerchantNormalizer.normalize("  The   New York  Times  ") == "the new york times")
    }
}
