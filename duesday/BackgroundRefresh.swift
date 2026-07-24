import BackgroundTasks
import CoreModels
import FeatureSettings
import Foundation
import Notifications
import SwiftData
import os

/// Conservative background refresh (docs/06): one BGAppRefreshTask that
/// syncs connected email accounts and replenishes scheduled reminders when
/// iOS grants opportunistic time. Never promised to the user as real-time —
/// the UI always shows "last synced".
@MainActor
final class BackgroundRefresh {
    static let taskIdentifier = "app.duesday.refresh"
    private static let logger = DuesdayLog.logger(category: "background")

    private let container: ModelContainer
    private let scheduler: ReminderScheduler

    init(container: ModelContainer, scheduler: ReminderScheduler) {
        self.container = container
        self.scheduler = scheduler
    }

    /// Must run before the app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handle(refreshTask)
            }
        }
    }

    /// Re-requests background time; iOS decides if and when it runs.
    func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on simulators and when background refresh is disabled.
            Self.logger.info("Background refresh not scheduled: \(error, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) async {
        scheduleNext()

        let work = Task { @MainActor in
            await self.syncAllAccounts()
        }
        task.expirationHandler = {
            work.cancel()
        }
        _ = await work.result
        task.setTaskCompleted(success: !work.isCancelled)
    }

    private func syncAllAccounts() async {
        let context = container.mainContext
        guard let accounts = try? context.fetch(FetchDescriptor<UserAccount>()) else { return }

        for account in accounts where account.connectionStatus == .connected {
            if Task.isCancelled { return }
            do {
                switch account.provider {
                case .gmail:
                    _ = try await GmailAccountService(context: context).sync(account: account)
                case .microsoft:
                    _ = try await MicrosoftAccountService(context: context).sync(account: account)
                }
            } catch {
                // Backoff is inherent: the next opportunistic slot retries.
                Self.logger.error("Background sync failed: \(error, privacy: .public)")
            }
        }

        // Replenish the nearest-N reminder window with fresh data.
        let subscriptions = (try? context.fetch(
            FetchDescriptor<Subscription>(predicate: #Predicate { $0.archivedAt == nil })
        )) ?? []
        await scheduler.refresh(
            subjects: subscriptions.map(\.reminderSubjectInput),
            preferences: NotificationPreferences.load()
        )
    }
}
