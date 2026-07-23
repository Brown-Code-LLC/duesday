import CoreModels
import DesignSystem
import Notifications
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Reminder preferences per the design spec: separate defaults for renewals
/// and trials (chip pickers), alert toggles, quiet hours, an optional daily
/// digest, and a truthful "how it will read" preview.
public struct NotificationSettingsView: View {
    private let onPreferencesChanged: () -> Void

    @State private var preferences = NotificationPreferences.load()
    @State private var permissionModel = NotificationPermissionModel()
    @Environment(\.openURL) private var openURL

    public init(onPreferencesChanged: @escaping () -> Void = {}) {
        self.onPreferencesChanged = onPreferencesChanged
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Reminders")
                    .font(.dsTitle(30))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, DS.Spacing.lg)

                if permissionModel.status == .denied {
                    deniedNotice
                        .padding(.bottom, DS.Spacing.lg)
                } else if permissionModel.status == .notDetermined {
                    enableFirst
                        .padding(.bottom, DS.Spacing.lg)
                }

                DSSectionHeader("Renewals — default")
                leadChips(
                    options: [0, 1, 3, 7, 14, 30],
                    isSelected: { preferences.defaultLeadDays == $0 },
                    toggle: { preferences.defaultLeadDays = $0 }
                )
                .padding(.vertical, DS.Spacing.md)

                DSSectionHeader("Trials — default")
                leadChips(
                    options: [7, 3, 1, 0],
                    isSelected: { preferences.trialLeadDays.contains($0) },
                    toggle: { toggleTrialLead($0) }
                )
                .padding(.top, DS.Spacing.md)
                Text("Trials can get more than one reminder — pick every lead time you want.")
                    .font(.dsBody(12))
                    .foregroundStyle(Color.dsInkTertiary)
                    .padding(.vertical, DS.Spacing.sm)

                togglesTable
                    .padding(.top, DS.Spacing.xs)

                DSCaptionLabel("How it will read")
                    .padding(.top, DS.Spacing.lg)
                    .accessibilityAddTraits(.isHeader)
                DSNotificationPreviewCard(
                    kicker: "Renews in \(max(preferences.defaultLeadDays, 1)) day\(preferences.defaultLeadDays == 1 ? "" : "s")",
                    time: previewTime,
                    message: preferences.includeAmounts
                        ? "Netflix renews Friday — $15.49."
                        : "Netflix renews Friday."
                )
                .padding(.top, DS.Spacing.sm)
                Text(preferences.includeAmounts
                     ? "Amounts appear in reminders. Anyone who can see your lock screen can see them."
                     : "Amounts stay out of reminders until you turn them on.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
                    .padding(.top, DS.Spacing.xs)
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.bottom, DS.Spacing.xl)
        }
        .background(Color.dsPaper)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await permissionModel.refresh() }
        .onChange(of: preferences) {
            preferences.save()
            onPreferencesChanged()
        }
    }

    // MARK: - Permission states

    private var deniedNotice: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Notifications are off for Duesday in the system settings. Preferences below take effect once they're allowed again.")
                .font(.dsBody(13))
                .foregroundStyle(Color.dsInkSecondary)
            #if os(iOS)
            Button("Open system settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.dsPrimary)
            #endif
        }
    }

    private var enableFirst: some View {
        Button("Enable notifications") {
            Task {
                await permissionModel.request()
                onPreferencesChanged()
            }
        }
        .buttonStyle(.dsPrimary)
    }

    // MARK: - Chips

    private func leadChips(
        options: [Int],
        isSelected: @escaping (Int) -> Bool,
        toggle: @escaping (Int) -> Void
    ) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { lead in
                DSFilterChip(
                    leadLabel(lead),
                    isSelected: isSelected(lead),
                    filled: true
                ) {
                    toggle(lead)
                    Haptics.selection()
                }
            }
        }
    }

    private func leadLabel(_ lead: Int) -> String {
        switch lead {
        case 0: "Day of"
        case 1: "1 day"
        default: "\(lead) days"
        }
    }

    private func toggleTrialLead(_ lead: Int) {
        if preferences.trialLeadDays.contains(lead) {
            // Keep at least one trial reminder.
            if preferences.trialLeadDays.count > 1 {
                preferences.trialLeadDays.removeAll { $0 == lead }
            }
        } else {
            preferences.trialLeadDays.append(lead)
            preferences.trialLeadDays.sort(by: >)
        }
    }

    // MARK: - Toggle rows

    private var togglesTable: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.dsDivider).frame(height: 1)
            toggleRow(
                "Price-change alerts",
                subtitle: "Arrives with email detection",
                isOn: $preferences.priceChangeAlerts
            )
            toggleRow(
                "Failed-payment alerts",
                subtitle: "Arrives with email detection",
                isOn: $preferences.failedPaymentAlerts
            )
            toggleRow(
                "Show amounts",
                subtitle: "Include prices in reminder text",
                isOn: $preferences.includeAmounts
            )
            toggleRow(
                "Quiet hours",
                subtitle: quietHoursSubtitle,
                isOn: $preferences.quietHoursEnabled
            )
            if preferences.quietHoursEnabled {
                HStack(spacing: DS.Spacing.lg) {
                    DatePicker(
                        "No reminders after",
                        selection: minutesBinding($preferences.quietStartMinutes),
                        displayedComponents: .hourAndMinute
                    )
                    .font(.dsBody(13))
                }
                .padding(.vertical, 6)
                HStack {
                    DatePicker(
                        "Resume at",
                        selection: minutesBinding($preferences.quietEndMinutes),
                        displayedComponents: .hourAndMinute
                    )
                    .font(.dsBody(13))
                }
                .padding(.bottom, 6)
                Rectangle().fill(Color.dsDivider).frame(height: 1)
            }
            toggleRow(
                "Group into a daily digest",
                subtitle: "One summary instead of separate alerts",
                isOn: $preferences.digestEnabled
            )
        }
        .tint(.dsAccent)
    }

    private var quietHoursSubtitle: String {
        guard preferences.quietHoursEnabled else { return "Reminders wait until morning" }
        let start = timeText(minutes: preferences.quietStartMinutes)
        let end = timeText(minutes: preferences.quietEndMinutes)
        return "\(start) – \(end)"
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsBody(14))
                    Text(subtitle)
                        .font(.dsBody(12))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private var previewTime: String {
        timeText(minutes: preferences.defaultTimeOfDayMinutes)
    }

    private func timeText(minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Bridges minutes-from-midnight storage to an hour/minute DatePicker.
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: .now)
                components.hour = minutes.wrappedValue / 60
                components.minute = minutes.wrappedValue % 60
                return calendar.date(from: components) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
