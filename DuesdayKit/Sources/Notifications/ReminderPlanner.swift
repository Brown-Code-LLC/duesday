import CoreModels
import Foundation

/// Value-type inputs decoupling planning from SwiftData: the planner is a pure
/// function over these, so scheduling logic is exhaustively testable.
public struct ReminderRuleSpec: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let type: ReminderType
    public let leadTimeDays: Int
    public let timeOfDayMinutes: Int
    public let isEnabled: Bool

    public init(id: UUID, type: ReminderType, leadTimeDays: Int, timeOfDayMinutes: Int, isEnabled: Bool) {
        self.id = id
        self.type = type
        self.leadTimeDays = leadTimeDays
        self.timeOfDayMinutes = timeOfDayMinutes
        self.isEnabled = isEnabled
    }
}

public struct ReminderSubjectInput: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let merchantName: String
    public let amount: Decimal?
    public let currencyCode: String?
    public let status: SubscriptionStatus
    public let isArchived: Bool
    public let nextBillingDate: Date?
    public let trialEndDate: Date?
    public let frequency: BillingFrequency
    public let customInterval: CustomInterval?
    public let rules: [ReminderRuleSpec]

    public init(
        id: UUID,
        merchantName: String,
        amount: Decimal?,
        currencyCode: String?,
        status: SubscriptionStatus,
        isArchived: Bool,
        nextBillingDate: Date?,
        trialEndDate: Date?,
        frequency: BillingFrequency,
        customInterval: CustomInterval?,
        rules: [ReminderRuleSpec]
    ) {
        self.id = id
        self.merchantName = merchantName
        self.amount = amount
        self.currencyCode = currencyCode
        self.status = status
        self.isArchived = isArchived
        self.nextBillingDate = nextBillingDate
        self.trialEndDate = trialEndDate
        self.frequency = frequency
        self.customInterval = customInterval
        self.rules = rules
    }
}

/// One notification the engine intends to schedule. `fireDateComponents` is a
/// calendar trigger (year/month/day/hour/minute), so DST shifts and time-zone
/// changes resolve at delivery time rather than being baked in as an epoch
/// offset (spec: notification engine).
public struct PlannedReminder: Hashable, Sendable {
    public let identifier: String
    /// Deep-link target; nil for digest summaries covering several entries.
    public let subscriptionID: UUID?
    public let fireDate: Date
    public let fireDateComponents: DateComponents
    public let title: String
    public let body: String
}

public enum ReminderPlanner {
    /// iOS caps pending requests at 64; we stay under it and replenish on
    /// foreground/refresh (nearest-N strategy).
    public static let maxScheduled = 56
    /// How far ahead occurrences are projected per rule.
    public static let horizonDays = 90
    private static let occurrencesPerRule = 6

    public struct Configuration: Sendable {
        public var maxScheduled: Int
        public var includeAmounts: Bool
        public var quietHours: QuietHours?
        /// Merge same-day reminders into one summary notification per day.
        public var digest: Bool

        public init(
            maxScheduled: Int = ReminderPlanner.maxScheduled,
            includeAmounts: Bool = false,
            quietHours: QuietHours? = nil,
            digest: Bool = false
        ) {
            self.maxScheduled = max(1, maxScheduled)
            self.includeAmounts = includeAmounts
            self.quietHours = quietHours
            self.digest = digest
        }

        public init(preferences: NotificationPreferences) {
            self.init(
                includeAmounts: preferences.includeAmounts,
                quietHours: preferences.quietHours,
                digest: preferences.digestEnabled
            )
        }
    }

    /// Plans the nearest notifications for all subjects: sorted by fire date,
    /// capped at `configuration.maxScheduled`, quiet hours applied, past fire
    /// times dropped.
    public static func plan(
        subjects: [ReminderSubjectInput],
        now: Date,
        calendar: Calendar = .current,
        configuration: Configuration = Configuration()
    ) -> [PlannedReminder] {
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        var planned: [PlannedReminder] = []
        for subject in subjects where !subject.isArchived && subject.status.countsTowardSpending {
            for rule in subject.rules where rule.isEnabled {
                planned.append(contentsOf: reminders(
                    for: rule,
                    subject: subject,
                    now: now,
                    horizonEnd: horizonEnd,
                    calendar: calendar,
                    configuration: configuration
                ))
            }
        }

        let ordered = planned.sorted { $0.fireDate < $1.fireDate }
        let limited = Array(ordered.prefix(configuration.maxScheduled))
        return configuration.digest ? digested(limited, calendar: calendar) : limited
    }

    /// Digest mode: days with more than one reminder collapse into a single
    /// summary firing at the day's earliest reminder time.
    private static func digested(_ reminders: [PlannedReminder], calendar: Calendar) -> [PlannedReminder] {
        let byDay = Dictionary(grouping: reminders) { reminder in
            calendar.startOfDay(for: reminder.fireDate)
        }
        return byDay.keys.sorted().flatMap { day -> [PlannedReminder] in
            let members = (byDay[day] ?? []).sorted { $0.fireDate < $1.fireDate }
            guard members.count > 1, let first = members.first else { return members }
            let names = members.map(\.title)
            let shown = names.prefix(3).joined(separator: ", ")
            let more = names.count > 3 ? " and \(names.count - 3) more" : ""
            let key = calendar.dateComponents([.year, .month, .day], from: day)
            return [PlannedReminder(
                identifier: "duesday.reminder.digest."
                    + String(format: "%04d%02d%02d", key.year ?? 0, key.month ?? 0, key.day ?? 0),
                subscriptionID: nil,
                fireDate: first.fireDate,
                fireDateComponents: first.fireDateComponents,
                title: "\(members.count) reminders today",
                body: "\(shown)\(more)."
            )]
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    private static func reminders(
        for rule: ReminderRuleSpec,
        subject: ReminderSubjectInput,
        now: Date,
        horizonEnd: Date,
        calendar: Calendar,
        configuration: Configuration
    ) -> [PlannedReminder] {
        let eventDates: [Date]
        switch rule.type {
        case .billingDay, .beforeBilling:
            eventDates = billingOccurrences(
                for: subject,
                now: now,
                horizonEnd: horizonEnd,
                calendar: calendar
            )
        case .trialEnd:
            eventDates = subject.trialEndDate.map { [$0] } ?? []
        case .priceIncrease, .paymentFailed, .syncFailure:
            // Event-driven types are posted when the triggering event is
            // detected (sync pipeline, Phase 3+), not pre-scheduled.
            eventDates = []
        }

        return eventDates.compactMap { eventDate in
            makeReminder(
                rule: rule,
                subject: subject,
                eventDate: eventDate,
                now: now,
                calendar: calendar,
                configuration: configuration
            )
        }
    }

    private static func billingOccurrences(
        for subject: ReminderSubjectInput,
        now: Date,
        horizonEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        guard let anchor = subject.nextBillingDate else { return [] }
        let window = DateInterval(start: min(now, anchor), end: horizonEnd)
        let occurrences = BillingSchedule.occurrences(
            in: window,
            anchor: anchor,
            frequency: subject.frequency,
            customInterval: subject.customInterval,
            calendar: calendar,
            limit: occurrencesPerRule
        )
        if occurrences.isEmpty, anchor <= horizonEnd {
            // Unknown step (custom without interval): honor the one known date.
            return [anchor]
        }
        return occurrences
    }

    private static func makeReminder(
        rule: ReminderRuleSpec,
        subject: ReminderSubjectInput,
        eventDate: Date,
        now: Date,
        calendar: Calendar,
        configuration: Configuration
    ) -> PlannedReminder? {
        guard let fireDay = calendar.date(byAdding: .day, value: -rule.leadTimeDays, to: eventDate) else {
            return nil
        }

        var minuteOfDay = rule.timeOfDayMinutes
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: fireDay)

        if let quiet = configuration.quietHours, quiet.contains(minuteOfDay: minuteOfDay) {
            // Defer into the end of the quiet window; overnight windows where
            // the fire time is in the late-evening span roll to the next day.
            if quiet.startMinutes > quiet.endMinutes, minuteOfDay >= quiet.startMinutes {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: fireDay) {
                    dayComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
                }
            }
            minuteOfDay = quiet.endMinutes
        }

        var fireComponents = dayComponents
        fireComponents.hour = minuteOfDay / 60
        fireComponents.minute = minuteOfDay % 60

        guard let fireDate = calendar.date(from: fireComponents), fireDate > now else {
            return nil
        }

        let eventDayKey = calendar.dateComponents([.year, .month, .day], from: eventDate)
        let identifier = "duesday.reminder.\(subject.id.uuidString).\(rule.id.uuidString)."
            + String(format: "%04d%02d%02d", eventDayKey.year ?? 0, eventDayKey.month ?? 0, eventDayKey.day ?? 0)

        return PlannedReminder(
            identifier: identifier,
            subscriptionID: subject.id,
            fireDate: fireDate,
            fireDateComponents: fireComponents,
            title: subject.merchantName,
            body: body(
                for: rule,
                subject: subject,
                includeAmount: configuration.includeAmounts
            )
        )
    }

    private static func body(
        for rule: ReminderRuleSpec,
        subject: ReminderSubjectInput,
        includeAmount: Bool
    ) -> String {
        let timing: String
        switch rule.leadTimeDays {
        case 0: timing = "today"
        case 1: timing = "tomorrow"
        default: timing = "in \(rule.leadTimeDays) days"
        }

        var text: String
        switch rule.type {
        case .trialEnd:
            text = "Your free trial ends \(timing)."
        case .billingDay, .beforeBilling:
            text = "Renews \(timing)."
        case .priceIncrease:
            text = "The price is changing."
        case .paymentFailed:
            text = "A payment needs attention."
        case .syncFailure:
            text = "Email sync needs attention."
        }

        if includeAmount, let amount = subject.amount, let code = subject.currencyCode {
            text += " \(Money(amount: amount, currencyCode: code).formatted())"
        }
        return text
    }
}
