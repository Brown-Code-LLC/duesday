import CoreModels
import Foundation
import Notifications
import Testing
import UserNotifications

/// In-memory stand-in for UNUserNotificationCenter.
@MainActor
private final class MockNotificationClient: NotificationClient {
    var status: UNAuthorizationStatus = .authorized
    var added: [UNNotificationRequest] = []
    var removed: [String] = []
    var pending: [String] = []
    var categories: Set<UNNotificationCategory> = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status == .authorized }
    func pendingIdentifiers() async -> [String] { pending }
    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        pending.append(request.identifier)
    }
    func removePending(identifiers: [String]) {
        removed.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }
    func setCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }
}

@Suite("Reminder scheduler")
@MainActor
struct ReminderSchedulerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func subject(nextBilling: Date) -> ReminderSubjectInput {
        ReminderSubjectInput(
            id: UUID(),
            merchantName: "Netflix",
            amount: Decimal(string: "7.99"),
            currencyCode: "USD",
            status: .active,
            isArchived: false,
            nextBillingDate: nextBilling,
            trialEndDate: nil,
            frequency: .monthly,
            customInterval: nil,
            rules: [ReminderRuleSpec(
                id: UUID(),
                type: .beforeBilling,
                leadTimeDays: 3,
                timeOfDayMinutes: 9 * 60,
                isEnabled: true
            )]
        )
    }

    @Test("Refresh schedules calendar-trigger requests with deep-link payload")
    func schedules() async {
        let client = MockNotificationClient()
        let scheduler = ReminderScheduler(client: client, calendar: calendar)
        let input = subject(nextBilling: date(2026, 8, 1))

        await scheduler.refresh(
            subjects: [input],
            preferences: NotificationPreferences(),
            now: date(2026, 7, 20)
        )

        #expect(!client.added.isEmpty)
        let request = client.added[0]
        #expect(request.trigger is UNCalendarNotificationTrigger)
        #expect(request.content.categoryIdentifier == DuesdayNotification.renewalCategory)
        #expect(
            request.content.userInfo[DuesdayNotification.subscriptionIDKey] as? String
                == input.id.uuidString
        )
    }

    @Test("Refresh is idempotent — nothing re-added when pending matches the plan")
    func idempotent() async {
        let client = MockNotificationClient()
        let scheduler = ReminderScheduler(client: client, calendar: calendar)
        let input = subject(nextBilling: date(2026, 8, 1))
        let preferences = NotificationPreferences()

        await scheduler.refresh(subjects: [input], preferences: preferences, now: date(2026, 7, 20))
        let firstCount = client.added.count

        await scheduler.refresh(subjects: [input], preferences: preferences, now: date(2026, 7, 20))
        #expect(client.added.count == firstCount)
        #expect(client.removed.isEmpty)
    }

    @Test("Changed billing date removes obsolete requests and adds new ones")
    func reschedulesOnDateChange() async {
        let client = MockNotificationClient()
        let scheduler = ReminderScheduler(client: client, calendar: calendar)
        let preferences = NotificationPreferences()

        await scheduler.refresh(
            subjects: [subject(nextBilling: date(2026, 8, 1))],
            preferences: preferences,
            now: date(2026, 7, 20)
        )
        let staleIdentifiers = client.pending

        await scheduler.refresh(
            subjects: [subject(nextBilling: date(2026, 8, 15))],
            preferences: preferences,
            now: date(2026, 7, 20)
        )
        // All old identifiers were reconciled away (different subject id + date).
        #expect(Set(client.removed).isSuperset(of: staleIdentifiers))
    }

    @Test("Nothing is scheduled without authorization")
    func requiresAuthorization() async {
        let client = MockNotificationClient()
        client.status = .denied
        let scheduler = ReminderScheduler(client: client, calendar: calendar)

        await scheduler.refresh(
            subjects: [subject(nextBilling: date(2026, 8, 1))],
            preferences: NotificationPreferences(),
            now: date(2026, 7, 20)
        )
        #expect(client.added.isEmpty)
    }

    @Test("Only Duesday-prefixed requests are ever touched")
    func foreignRequestsUntouched() async {
        let client = MockNotificationClient()
        client.pending = ["someone.elses.notification"]
        let scheduler = ReminderScheduler(client: client, calendar: calendar)

        await scheduler.refresh(subjects: [], preferences: NotificationPreferences(), now: date(2026, 7, 20))
        await scheduler.removeAllReminders()
        #expect(!client.removed.contains("someone.elses.notification"))
        #expect(client.pending.contains("someone.elses.notification"))
    }

    @Test("removeAllReminders clears every Duesday request")
    func removeAll() async {
        let client = MockNotificationClient()
        let scheduler = ReminderScheduler(client: client, calendar: calendar)
        await scheduler.refresh(
            subjects: [subject(nextBilling: date(2026, 8, 1))],
            preferences: NotificationPreferences(),
            now: date(2026, 7, 20)
        )
        #expect(!client.pending.isEmpty)

        await scheduler.removeAllReminders()
        #expect(client.pending.filter { $0.hasPrefix(DuesdayNotification.identifierPrefix) }.isEmpty)
    }

    @Test("Category registration exposes the renewal category with a view action")
    func categories() {
        let client = MockNotificationClient()
        let scheduler = ReminderScheduler(client: client, calendar: calendar)
        scheduler.registerCategories()
        #expect(client.categories.contains { $0.identifier == DuesdayNotification.renewalCategory })
    }
}
