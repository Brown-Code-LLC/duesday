import CoreModels
import Foundation
import UserNotifications
import os

/// Seam over `UNUserNotificationCenter` so scheduling is testable with a mock.
public protocol NotificationClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
    func setCategories(_ categories: Set<UNNotificationCategory>)
}

public final class SystemNotificationClient: NotificationClient {
    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}

public nonisolated enum DuesdayNotification {
    public static let renewalCategory = "DUESDAY_RENEWAL"
    public static let viewAction = "DUESDAY_VIEW"
    public static let subscriptionIDKey = "subscriptionID"
    public static let identifierPrefix = "duesday.reminder."
}

/// Turns reminder plans into scheduled local notifications. Refresh is
/// idempotent: it diffs against pending Duesday requests, removes obsolete
/// ones (changed billing dates, deleted subscriptions), and adds only what's
/// missing — replenishing the nearest-N window each time it runs.
public final class ReminderScheduler {
    private let client: NotificationClient
    private let calendar: Calendar
    private static let logger = DuesdayLog.logger(category: "notifications")

    public init(client: NotificationClient = SystemNotificationClient(), calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    public func registerCategories() {
        let view = UNNotificationAction(
            identifier: DuesdayNotification.viewAction,
            title: "View subscription",
            options: [.foreground]
        )
        let renewal = UNNotificationCategory(
            identifier: DuesdayNotification.renewalCategory,
            actions: [view],
            intentIdentifiers: []
        )
        client.setCategories([renewal])
    }

    /// Re-plans and reconciles pending notifications. No-op unless authorized.
    public func refresh(
        subjects: [ReminderSubjectInput],
        preferences: NotificationPreferences,
        now: Date = .now
    ) async {
        let status = await client.authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let plan = ReminderPlanner.plan(
            subjects: subjects,
            now: now,
            calendar: calendar,
            configuration: ReminderPlanner.Configuration(preferences: preferences)
        )
        let plannedByID = Dictionary(uniqueKeysWithValues: plan.map { ($0.identifier, $0) })

        let pending = await client.pendingIdentifiers()
            .filter { $0.hasPrefix(DuesdayNotification.identifierPrefix) }
        let pendingSet = Set(pending)

        let stale = pending.filter { plannedByID[$0] == nil }
        if !stale.isEmpty {
            client.removePending(identifiers: stale)
        }

        for reminder in plan where !pendingSet.contains(reminder.identifier) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = DuesdayNotification.renewalCategory
            if let subscriptionID = reminder.subscriptionID {
                content.userInfo = [
                    DuesdayNotification.subscriptionIDKey: subscriptionID.uuidString
                ]
            }

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: reminder.fireDateComponents,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await client.add(request)
            } catch {
                Self.logger.error("Failed to schedule reminder: \(error, privacy: .public)")
            }
        }
    }

    /// Removes every Duesday-scheduled notification (used by delete-all-data).
    public func removeAllReminders() async {
        let ours = await client.pendingIdentifiers()
            .filter { $0.hasPrefix(DuesdayNotification.identifierPrefix) }
        if !ours.isEmpty {
            client.removePending(identifiers: ours)
        }
    }
}
