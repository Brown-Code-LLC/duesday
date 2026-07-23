import DesignSystem
import Notifications
import SwiftUI

/// Onboarding per the design spec — three pages in the ledger voice:
/// value (numbered i/ii/iii rows), the reads/never-reads privacy contract,
/// and notification education with a truthful preview. The system permission
/// prompt appears only after the education page and only on explicit opt-in.
public struct OnboardingView: View {
    @State private var page = 0
    @State private var permissionModel = NotificationPermissionModel()
    @State private var isRequesting = false
    private let onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                valuePage.tag(0)
                privacyPage.tag(1)
                notificationsPage.tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            pageDots
                .padding(.bottom, DS.Spacing.md)

            footer
                .padding(.horizontal, DS.screenMargin)
                .padding(.bottom, DS.Spacing.xl)
        }
        .background(Color.dsPaper)
    }

    // MARK: - Page 1 · Value (spec 1b)

    private var valuePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Duesday")
                Text("Every renewal,\non your ledger.")
                    .font(.dsTitle(40))
                    .lineSpacing(2)
                    .padding(.top, DS.Spacing.md)
                    .accessibilityAddTraits(.isHeader)
                Text("Subscriptions, memberships, utilities and trials — entered by you today, found in email receipts soon, and remembered before they charge you again.")
                    .font(.dsBody(14.5))
                    .lineSpacing(5)
                    .foregroundStyle(Color.dsInkSecondary)
                    .padding(.top, DS.Spacing.lg)

                VStack(spacing: 0) {
                    numberedRow("i.", title: "Find", body: "Receipts and renewal notices, detected from connected email — arriving in a coming update.", topRule: true)
                    numberedRow("ii.", title: "Remind", body: "A quiet word before trials end and payments renew.")
                    numberedRow("iii.", title: "Understand", body: "What a month truly costs, and where it could cost less.")
                }
                .padding(.top, DS.Spacing.xl)
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.top, DS.Spacing.xxl)
        }
    }

    private func numberedRow(_ numeral: String, title: String, body bodyText: String, topRule: Bool = false) -> some View {
        VStack(spacing: 0) {
            if topRule {
                Rectangle().fill(Color.dsDivider).frame(height: 1)
            }
            HStack(alignment: .top, spacing: 14) {
                Text(numeral)
                    .font(.dsSerif(22))
                    .foregroundStyle(Color.dsAccentDeep)
                    .frame(width: 26, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.dsBodyStrong(15))
                    Text(bodyText)
                        .font(.dsBody(13))
                        .lineSpacing(3)
                        .foregroundStyle(Color.dsInkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.lg)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Page 2 · Privacy contract (spec 1c)

    private var privacyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Before anything else")
                Text("What Duesday\ncan read")
                    .font(.dsTitle(34))
                    .padding(.top, DS.Spacing.md)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    contractCaption("Duesday reads", color: .dsAccentDeep)
                    contractLine("Entries you add by hand — always")
                    contractLine("When email arrives: receipts, renewal notices and trial confirmations")
                    contractLine("Sender, subject, amount and billing date — read-only")

                    contractCaption("Duesday never reads", color: .dsInkSecondary)
                        .padding(.top, DS.Spacing.lg)
                    contractLine("Personal conversations or attachments", muted: true)
                    contractLine("Your contacts, calendar, texts or other apps", muted: true)
                    contractLine("Banking or card data — Duesday never sees full card numbers", muted: true)
                }
                .padding(.top, DS.Spacing.lg)

                Text("Nothing joins your ledger until you confirm it. Disconnect at any time and imported email data is deleted with it.")
                    .font(.dsBody(13))
                    .lineSpacing(4)
                    .foregroundStyle(Color.dsInkSecondary)
                    .padding(.top, DS.Spacing.lg)
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.top, DS.Spacing.xxl)
        }
    }

    private func contractCaption(_ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Color.dsDivider).frame(height: 1)
            Text(text)
                .font(.dsCaption(12))
                .textCase(.uppercase)
                .tracking(DS.tracking(0.14, size: 12))
                .foregroundStyle(color)
                .padding(.top, DS.Spacing.sm)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func contractLine(_ text: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.dsBody(14))
                .lineSpacing(3)
                .foregroundStyle(muted ? Color.dsInkSecondary : Color.dsInk)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    // MARK: - Page 3 · Notification education (spec 1d)

    private var notificationsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                kicker("Reminders")
                Text("A word before\nthe charge")
                    .font(.dsTitle(34))
                    .padding(.top, DS.Spacing.md)
                    .accessibilityAddTraits(.isHeader)
                Text("Duesday only speaks up when money is about to move: trials ending, renewals due, prices rising, payments failing. Never marketing.")
                    .font(.dsBody(14))
                    .lineSpacing(4)
                    .foregroundStyle(Color.dsInkSecondary)
                    .padding(.top, DS.Spacing.md)

                VStack(spacing: DS.Spacing.sm) {
                    DSNotificationPreviewCard(
                        kicker: "Trial ending",
                        time: "9:00 AM",
                        message: "Your trial ends Sunday. It becomes a paid plan unless you cancel first."
                    )
                    DSNotificationPreviewCard(
                        kicker: "Renews in 3 days",
                        time: "9:00 AM",
                        message: "Netflix renews Friday."
                    )
                }
                .padding(.top, DS.Spacing.xl)

                Text("You choose the timing per entry. Quiet hours respected. Amounts stay off your lock screen unless you opt in.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
                    .padding(.top, DS.Spacing.md)
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.top, DS.Spacing.xxl)
        }
    }

    // MARK: - Chrome

    private func kicker(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption(10.5))
            .textCase(.uppercase)
            .tracking(DS.tracking(0.2, size: 10.5))
            .foregroundStyle(Color.dsAccentDeep)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == page ? Color.dsAccentDeep : Color.dsChipBorder)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var footer: some View {
        if page < 2 {
            Button("Continue") {
                withAnimation { page += 1 }
            }
            .buttonStyle(.dsPrimary)
        } else {
            VStack(spacing: DS.Spacing.sm) {
                Button {
                    enableReminders()
                } label: {
                    if isRequesting {
                        ProgressView().tint(Color.dsAccentDeep)
                    } else {
                        Text("Enable notifications")
                    }
                }
                .buttonStyle(.dsPrimary)
                .disabled(isRequesting)

                Button("Not now") { onFinished() }
                    .buttonStyle(.dsQuiet)
                    .accessibilityHint("You can enable reminders later in Settings")
            }
        }
    }

    private func enableReminders() {
        isRequesting = true
        Task {
            await permissionModel.request()
            isRequesting = false
            Haptics.success()
            onFinished()
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
