import AppSecurity
import CoreModels
import DesignSystem
import FeatureCalendar
import FeatureInsights
import FeatureOnboarding
import FeatureOverview
import FeatureSettings
import FeatureSubscriptions
import Notifications
import SwiftData
import SwiftUI

struct RootView: View {
    @Bindable var router: AppRouter
    let storageWarning: String?
    let appLock: AppLockModel
    let scheduler: ReminderScheduler
    /// Called when the app backgrounds so the next opportunistic refresh is
    /// requested (BGAppRefreshTask).
    var onEnterBackground: () -> Void = {}

    @AppStorage("duesday.onboarding.complete") private var onboardingComplete = false
    @State private var isPresentingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Subscription> { $0.archivedAt == nil })
    private var subscriptions: [Subscription]

    var body: some View {
        // Four tabs per the design spec; Settings opens from the Overview
        // monogram (and from notification-denied states inside features).
        TabView(selection: $router.selectedTab) {
            Tab("Overview", systemImage: "house", value: .overview) {
                OverviewView(
                    onAddSubscription: { router.selectedTab = .subscriptions },
                    onOpenSettings: { isPresentingSettings = true }
                )
            }
            Tab("Subscriptions", systemImage: "list.bullet", value: .subscriptions) {
                SubscriptionListView(externalTarget: $router.pendingSubscriptionID)
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                RenewalCalendarView()
            }
            Tab("Insights", systemImage: "chart.bar", value: .insights) {
                InsightsView()
            }
        }
        .tint(Color.dsAccentDeep)
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView(
                storageWarning: storageWarning,
                appLock: appLock,
                onPreferencesChanged: { refreshReminders() }
            )
        }
        .fullScreenCover(isPresented: needsOnboardingBinding) {
            OnboardingView {
                onboardingComplete = true
                refreshReminders()
            }
            .interactiveDismissDisabled()
        }
        .overlay {
            // Redacts the app-switcher snapshot whenever the app isn't active
            // (privacy model: no sensitive content in screenshots).
            if scenePhase != .active && !appLock.isLocked {
                PrivacyRedactionView()
            }
        }
        .overlay {
            if appLock.isLocked {
                AppLockScreen(appLock: appLock)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                appLock.lock()
                onEnterBackground()
            case .active:
                refreshReminders()
            default:
                break
            }
        }
        .onChange(of: router.pendingSubscriptionID) { _, target in
            if target != nil {
                router.selectedTab = .subscriptions
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            refreshReminders()
        }
        .task {
            scheduler.registerCategories()
            refreshReminders()
            #if DEBUG
            // Diagnostic hook: exercises the onboarding "Enable notifications"
            // path without a tap, so the flow can be driven from automation.
            if ProcessInfo.processInfo.arguments.contains("-duesday-auto-enable-notifications") {
                await NotificationPermissionModel().request()
                onboardingComplete = true
                refreshReminders()
            }
            #endif
        }
    }

    private var needsOnboardingBinding: Binding<Bool> {
        Binding(
            get: { !onboardingComplete },
            set: { if !$0 { onboardingComplete = true } }
        )
    }

    /// Replenishes the nearest-N scheduled notifications from current data.
    private func refreshReminders() {
        let subjects = subscriptions.map(\.reminderSubjectInput)
        let preferences = NotificationPreferences.load()
        Task {
            await scheduler.refresh(subjects: subjects, preferences: preferences)
        }
    }
}

/// Opaque cover while the app is inactive/backgrounded so amounts and
/// merchants never appear in the app switcher.
private struct PrivacyRedactionView: View {
    var body: some View {
        ZStack {
            Color.dsPaper.ignoresSafeArea()
            VStack(spacing: DS.Spacing.lg) {
                Rectangle()
                    .fill(Color.dsAccent)
                    .frame(width: 34, height: 1)
                Text("Duesday")
                    .font(.dsDisplay(40))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Face ID / passcode gate. Attempts authentication on appear and offers a
/// retry button if it fails or is canceled.
private struct AppLockScreen: View {
    let appLock: AppLockModel
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color.dsPaper.ignoresSafeArea()
            VStack(spacing: DS.Spacing.xl) {
                Rectangle()
                    .fill(Color.dsAccent)
                    .frame(width: 34, height: 1)
                Text("Duesday")
                    .font(.dsDisplay(44))
                Text("Locked")
                    .font(.dsCaption(11))
                    .textCase(.uppercase)
                    .tracking(DS.tracking(0.22, size: 11))
                    .foregroundStyle(Color.dsAccentDeep)
                Button {
                    attemptUnlock()
                } label: {
                    if isAuthenticating {
                        ProgressView().tint(Color.dsAccentDeep)
                    } else {
                        Text("Unlock with \(appLock.biometryDescription)")
                    }
                }
                .buttonStyle(.dsPrimary)
                .frame(maxWidth: 300)
                .disabled(isAuthenticating)
            }
            .padding()
        }
        .task { attemptUnlock() }
    }

    private func attemptUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            await appLock.unlock()
            isAuthenticating = false
        }
    }
}
