import CoreModels
import Notifications
import Persistence
import AppSecurity
import SwiftData
import SwiftUI
import UserNotifications
import os

#if DEBUG
import TestingSupport
#endif

@main
struct DuesdayApp: App {
    private let bootstrap: PersistenceController.Bootstrap
    private let router = AppRouter()
    private let appLock = AppLockModel()
    private let scheduler = ReminderScheduler()
    /// Strong reference required — UNUserNotificationCenter.delegate is weak.
    private let notificationRouter = NotificationRouter()

    init() {
        let useSampleData: Bool
        #if DEBUG
        // DEBUG-only sample environment (ADR-9): in-memory store seeded with
        // deterministic data, activated via launch argument for previews,
        // demos, and UI tests. Release builds contain no seeding path.
        useSampleData = ProcessInfo.processInfo.arguments.contains("-duesday-sample-data")
        #else
        useSampleData = false
        #endif

        do {
            bootstrap = try PersistenceController.bootstrap(inMemory: useSampleData)
        } catch {
            // bootstrap already fell back to in-memory once; reaching this
            // means even an in-memory container cannot be created — the schema
            // itself is invalid and no meaningful execution is possible.
            fatalError("Unrecoverable storage failure: \(error)")
        }

        #if DEBUG
        if useSampleData {
            do {
                try SampleData.seed(into: bootstrap.controller.mainContext)
            } catch {
                DuesdayLog.logger(category: "app")
                    .error("Sample data seeding failed: \(error, privacy: .public)")
            }
        }
        #endif

        let router = self.router
        notificationRouter.onOpenSubscription = { id in
            router.openSubscription(id: id)
        }
        UNUserNotificationCenter.current().delegate = notificationRouter
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                router: router,
                storageWarning: storageWarning,
                appLock: appLock,
                scheduler: scheduler
            )
        }
        .modelContainer(bootstrap.controller.container)
    }

    private var storageWarning: String? {
        guard bootstrap.storeError != nil else { return nil }
        return "Duesday couldn't open its storage, so changes made now won't be saved. Restart the app; if this keeps happening, reinstalling may be required."
    }
}
