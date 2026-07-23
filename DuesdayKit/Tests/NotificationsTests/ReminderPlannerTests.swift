import CoreModels
import Foundation
import Notifications
import Testing

@Suite("Reminder planning")
@MainActor
struct ReminderPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func subject(
        merchant: String = "Netflix",
        amount: Decimal? = Decimal(string: "7.99"),
        currency: String? = "USD",
        status: SubscriptionStatus = .active,
        isArchived: Bool = false,
        nextBilling: Date?,
        trialEnd: Date? = nil,
        frequency: BillingFrequency = .monthly,
        rules: [ReminderRuleSpec]
    ) -> ReminderSubjectInput {
        ReminderSubjectInput(
            id: UUID(),
            merchantName: merchant,
            amount: amount,
            currencyCode: currency,
            status: status,
            isArchived: isArchived,
            nextBillingDate: nextBilling,
            trialEndDate: trialEnd,
            frequency: frequency,
            customInterval: nil,
            rules: rules
        )
    }

    private func rule(
        type: ReminderType = .beforeBilling,
        leadDays: Int = 3,
        timeMinutes: Int = 9 * 60,
        enabled: Bool = true
    ) -> ReminderRuleSpec {
        ReminderRuleSpec(
            id: UUID(),
            type: type,
            leadTimeDays: leadDays,
            timeOfDayMinutes: timeMinutes,
            isEnabled: enabled
        )
    }

    @Test("Three-days-before fires 3 days before billing at the chosen time")
    func leadTime() {
        let now = date(2026, 7, 20)
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 8, 1), rules: [rule(leadDays: 3)])],
            now: now,
            calendar: calendar
        )
        let first = plan.first
        #expect(first != nil)
        #expect(first?.fireDate == date(2026, 7, 29, hour: 9))
        #expect(first?.fireDateComponents.hour == 9)
        #expect(first?.fireDateComponents.minute == 0)
    }

    @Test("Billing-day rule fires on the billing day itself")
    func billingDay() {
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 8, 1), rules: [rule(type: .billingDay, leadDays: 0)])],
            now: date(2026, 7, 20),
            calendar: calendar
        )
        #expect(plan.first?.fireDate == date(2026, 8, 1, hour: 9))
        #expect(plan.first?.body == "Renews today.")
    }

    @Test("Trial-end rule uses the trial date, not the billing date")
    func trialEnd() {
        let plan = ReminderPlanner.plan(
            subjects: [subject(
                nextBilling: date(2026, 9, 15),
                trialEnd: date(2026, 8, 5),
                rules: [rule(type: .trialEnd, leadDays: 1)]
            )],
            now: date(2026, 7, 20),
            calendar: calendar
        )
        // The billing rule wasn't set; only the trial reminder exists.
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == date(2026, 8, 4, hour: 9))
        #expect(plan.first?.body == "Your free trial ends tomorrow.")
    }

    @Test("Monthly subscriptions plan multiple future occurrences in the horizon")
    func multipleOccurrences() {
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 8, 1), rules: [rule(leadDays: 3)])],
            now: date(2026, 7, 20),
            calendar: calendar
        )
        #expect(plan.count >= 2)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test("Disabled rules, canceled and archived subscriptions plan nothing")
    func exclusions() {
        let subjects = [
            subject(nextBilling: date(2026, 8, 1), rules: [rule(enabled: false)]),
            subject(status: .canceled, nextBilling: date(2026, 8, 1), rules: [rule()]),
            subject(isArchived: true, nextBilling: date(2026, 8, 1), rules: [rule()]),
        ]
        let plan = ReminderPlanner.plan(subjects: subjects, now: date(2026, 7, 20), calendar: calendar)
        #expect(plan.isEmpty)
    }

    @Test("Fire times already in the past are dropped")
    func pastFireTimes() {
        // Billing tomorrow, but the 3-day-before fire time was 2 days ago.
        // Only future occurrences remain.
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 7, 21), rules: [rule(leadDays: 3)])],
            now: date(2026, 7, 20),
            calendar: calendar
        )
        #expect(plan.allSatisfy { $0.fireDate > date(2026, 7, 20) })
    }

    @Test("Plan is capped at the configured maximum, keeping the nearest")
    func capAtMaximum() {
        let subjects = (0..<30).map { index in
            subject(
                merchant: "Service \(index)",
                nextBilling: date(2026, 8, 1 + (index % 20)),
                rules: [rule(leadDays: 0, timeMinutes: 9 * 60), rule(leadDays: 3)]
            )
        }
        let configuration = ReminderPlanner.Configuration(maxScheduled: 10)
        let plan = ReminderPlanner.plan(
            subjects: subjects,
            now: date(2026, 7, 20),
            calendar: calendar,
            configuration: configuration
        )
        #expect(plan.count == 10)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
    }

    @Test("Amounts appear in bodies only when opted in")
    func amountOptIn() {
        let subjects = [subject(nextBilling: date(2026, 8, 1), rules: [rule(leadDays: 3)])]
        let without = ReminderPlanner.plan(
            subjects: subjects, now: date(2026, 7, 20), calendar: calendar,
            configuration: .init(includeAmounts: false)
        )
        let with = ReminderPlanner.plan(
            subjects: subjects, now: date(2026, 7, 20), calendar: calendar,
            configuration: .init(includeAmounts: true)
        )
        #expect(without.first?.body.contains("7.99") == false)
        #expect(with.first?.body.contains("7.99") == true)
    }

    @Test("Quiet hours defer a late-evening reminder to the next morning")
    func quietHoursOvernight() {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 8, 1), rules: [rule(leadDays: 3, timeMinutes: 22 * 60 + 30)])],
            now: date(2026, 7, 20),
            calendar: calendar,
            configuration: .init(quietHours: quiet)
        )
        // 22:30 on Jul 29 falls in quiet hours → deferred to Jul 30, 07:00.
        #expect(plan.first?.fireDate == date(2026, 7, 30, hour: 7))
    }

    @Test("Quiet hours shift an early-morning reminder to the window end same day")
    func quietHoursMorning() {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let plan = ReminderPlanner.plan(
            subjects: [subject(nextBilling: date(2026, 8, 1), rules: [rule(leadDays: 3, timeMinutes: 6 * 60)])],
            now: date(2026, 7, 20),
            calendar: calendar,
            configuration: .init(quietHours: quiet)
        )
        #expect(plan.first?.fireDate == date(2026, 7, 29, hour: 7))
    }

    @Test("Identifiers are stable for the same rule and event date")
    func stableIdentifiers() {
        let fixedRule = rule(leadDays: 3)
        let fixedSubject = subject(nextBilling: date(2026, 8, 1), rules: [fixedRule])
        let planA = ReminderPlanner.plan(subjects: [fixedSubject], now: date(2026, 7, 18), calendar: calendar)
        let planB = ReminderPlanner.plan(subjects: [fixedSubject], now: date(2026, 7, 20), calendar: calendar)
        #expect(planA.first?.identifier == planB.first?.identifier)
    }
}

@Suite("Quiet hours window")
struct QuietHoursTests {
    @Test("Overnight windows wrap midnight")
    func overnight() {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(quiet.contains(minuteOfDay: 23 * 60))
        #expect(quiet.contains(minuteOfDay: 3 * 60))
        #expect(!quiet.contains(minuteOfDay: 12 * 60))
        #expect(!quiet.contains(minuteOfDay: 7 * 60))
    }

    @Test("Same-day windows are half-open")
    func sameDay() {
        let quiet = QuietHours(startMinutes: 13 * 60, endMinutes: 14 * 60)
        #expect(quiet.contains(minuteOfDay: 13 * 60))
        #expect(!quiet.contains(minuteOfDay: 14 * 60))
    }

    @Test("Degenerate window contains nothing")
    func degenerate() {
        let quiet = QuietHours(startMinutes: 9 * 60, endMinutes: 9 * 60)
        #expect(!quiet.contains(minuteOfDay: 9 * 60))
    }
}
