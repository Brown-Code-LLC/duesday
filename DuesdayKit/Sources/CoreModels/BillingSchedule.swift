import Foundation

/// Calendar-correct projection of billing dates from an anchor date.
///
/// All arithmetic uses `Calendar` component math (never 86 400-second offsets),
/// so DST transitions and month-end clamping behave correctly. Occurrences are
/// always computed as `anchor + k × step` — not by repeatedly adding to a
/// clamped result — so "the 31st" doesn't permanently drift to "the 28th"
/// after passing February.
public enum BillingSchedule {
    /// Hard cap on projection iterations; well beyond any realistic horizon
    /// (weekly for ~19 years) and guarantees termination on degenerate input.
    private static let maxIterations = 1000

    /// The component step for one billing period, or nil when the frequency is
    /// `.custom` without a valid interval (unknown — never guessed).
    public static func step(
        frequency: BillingFrequency,
        customInterval: CustomInterval?
    ) -> DateComponents? {
        switch frequency {
        case .weekly: DateComponents(day: 7)
        case .monthly: DateComponents(month: 1)
        case .quarterly: DateComponents(month: 3)
        case .semiannual: DateComponents(month: 6)
        case .annual: DateComponents(year: 1)
        case .custom:
            customInterval.flatMap { interval in
                guard interval.count >= 1 else { return nil }
                return switch interval.unit {
                case .day: DateComponents(day: interval.count)
                case .week: DateComponents(day: interval.count * 7)
                case .month: DateComponents(month: interval.count)
                case .year: DateComponents(year: interval.count)
                }
            }
        }
    }

    private static func multiplied(_ step: DateComponents, by factor: Int) -> DateComponents {
        DateComponents(
            year: step.year.map { $0 * factor },
            month: step.month.map { $0 * factor },
            day: step.day.map { $0 * factor }
        )
    }

    /// First billing date at or after `reference`, projected from `anchor`.
    public static func nextDate(
        onOrAfter reference: Date,
        anchor: Date,
        frequency: BillingFrequency,
        customInterval: CustomInterval? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard let step = step(frequency: frequency, customInterval: customInterval) else {
            return nil
        }
        if anchor >= reference { return anchor }

        for k in 1...maxIterations {
            guard let candidate = calendar.date(byAdding: multiplied(step, by: k), to: anchor) else {
                return nil
            }
            if candidate >= reference { return candidate }
        }
        return nil
    }

    /// All projected billing dates that fall inside `interval` (start inclusive,
    /// end exclusive), capped at `limit`.
    public static func occurrences(
        in interval: DateInterval,
        anchor: Date,
        frequency: BillingFrequency,
        customInterval: CustomInterval? = nil,
        calendar: Calendar = .current,
        limit: Int = 100
    ) -> [Date] {
        guard let step = step(frequency: frequency, customInterval: customInterval),
              limit > 0
        else { return [] }

        var results: [Date] = []
        var k = 0
        while k <= maxIterations {
            let date: Date?
            if k == 0 {
                date = anchor
            } else {
                date = calendar.date(byAdding: multiplied(step, by: k), to: anchor)
            }
            guard let date else { break }
            if date >= interval.end { break }
            if date >= interval.start {
                results.append(date)
                if results.count >= limit { break }
            }
            k += 1
        }
        return results
    }
}
