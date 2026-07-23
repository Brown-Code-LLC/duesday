import DesignSystem
import SwiftUI

/// Plain-language privacy explanation (required feature 2). This copy is
/// product copy, not legal text; the legal privacy policy is linked at
/// submission time. [PLACEHOLDER: legal privacy policy URL — Phase 7]
public struct PrivacyExplanationView: View {
    public init() {}

    public var body: some View {
        List {
            Section("Your data stays yours") {
                explanation(
                    icon: "iphone",
                    title: "Stored on your device",
                    body: "Subscriptions, amounts, and reminders are stored locally on this device. Nothing is uploaded in the current version."
                )
                explanation(
                    icon: "hand.raised",
                    title: "No tracking, no ads",
                    body: "Duesday contains no advertising and does not sell or share your information."
                )
            }

            Section("When email scanning arrives") {
                explanation(
                    icon: "envelope.badge.shield.half.filled",
                    title: "Read-only, and only what you connect",
                    body: "You choose which Gmail or Outlook account to connect. Access is read-only, uses targeted searches for receipts and renewals, and never downloads your whole mailbox."
                )
                explanation(
                    icon: "checkmark.rectangle.stack",
                    title: "You review everything",
                    body: "Detected subscriptions go to a review queue. Nothing is added, changed, or acted on without your confirmation."
                )
                explanation(
                    icon: "key",
                    title: "Credentials in the Keychain",
                    body: "Sign-in uses the provider's official authorization. Duesday never sees your password, and tokens are stored only in the system Keychain."
                )
                explanation(
                    icon: "trash",
                    title: "Delete any time",
                    body: "Disconnecting an account revokes access and lets you delete everything that was imported from it."
                )
            }

            Section("What Duesday cannot do") {
                explanation(
                    icon: "xmark.shield",
                    title: "No access to Apple Mail, Messages, or other apps",
                    body: "iOS does not allow apps to read Apple Mail, iMessage, other apps' data, or your App Store purchase history — and Duesday never claims otherwise. You can share an email or receipt into Duesday instead."
                )
            }
        }
        .navigationTitle("Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func explanation(icon: String, title: String, body bodyText: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.dsAccent)
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        PrivacyExplanationView()
    }
}
