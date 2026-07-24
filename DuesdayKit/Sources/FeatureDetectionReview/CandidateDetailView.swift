import CoreModels
import DesignSystem
import FeatureSubscriptions
import Persistence
import SwiftData
import SwiftUI

/// Detection detail per the design spec (frame 1h): the evidence, quoted;
/// every field editable before it counts. Confirm / edit-then-confirm /
/// merge / ignore / not-a-subscription.
public struct CandidateDetailView: View {
    @Bindable var candidate: DetectionCandidate
    @State private var isPresentingEdit = false
    @State private var editWasSaved = false
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    public init(candidate: DetectionCandidate) {
        self.candidate = candidate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityHeader
                    .padding(.top, DS.Spacing.sm)
                fieldsTable
                    .padding(.top, DS.Spacing.lg)
                evidenceSection
                if let duplicate = duplicateSubscription {
                    mergeSection(duplicate)
                }
                actionButtons
                    .padding(.vertical, DS.Spacing.xl)
            }
            .padding(.horizontal, DS.screenMargin)
        }
        .background(Color.dsPaper)
        .navigationTitle("Detection")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isPresentingEdit, onDismiss: resolveAfterEditIfSaved) {
            SubscriptionFormView(mode: .create, prefill: prefill) {
                editWasSaved = true
            }
        }
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Sections

    private var identityHeader: some View {
        HStack(spacing: 14) {
            DSGlyphBox(for: candidate.merchantName ?? "?", size: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.merchantName ?? "Unknown merchant")
                    .font(.dsTitle(26))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    DSTagPill(confidenceLabel, style: highConfidence ? .accent : .neutral, capsule: true)
                    if candidate.trialEndDate != nil {
                        DSTagPill("Trial", style: .accent, capsule: true)
                    }
                }
            }
            Spacer()
        }
    }

    private var highConfidence: Bool {
        candidate.confidenceScore >= DetectionCandidate.bulkConfirmThreshold
    }

    private var confidenceLabel: String {
        "\(Int((candidate.confidenceScore * 100).rounded()))% match"
    }

    private var fieldsTable: some View {
        VStack(spacing: 0) {
            DSLedgerRow("Amount", topRule: true) {
                if let amount = candidate.amount, let currency = candidate.currencyCode {
                    Text(Money(amount: amount, currencyCode: currency).formatted())
                } else {
                    unknownValue
                }
            }
            DSLedgerRow("Billed") {
                if let frequency = candidate.billingFrequency {
                    Text(frequencyText(frequency))
                } else {
                    unknownValue
                }
            }
            if let next = candidate.nextBillingDate {
                DSLedgerRow("Next charge", value: next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            }
            if let trial = candidate.trialEndDate {
                DSLedgerRow("Trial ends") {
                    Text(trial.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .foregroundStyle(Color.dsAccentDeep)
                }
            }
            DSLedgerRow("Found", value: candidate.detectedDate.formatted(.dateTime.month(.abbreviated).day().year()))
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    private var unknownValue: Text {
        Text("Unknown — edit to fill in")
            .foregroundStyle(Color.dsInkTertiary)
    }

    private func frequencyText(_ frequency: BillingFrequency) -> String {
        if frequency == .custom, let interval = candidate.customInterval {
            return "Every \(interval.count) \(interval.unit.displayName)"
        }
        return frequency.displayName
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Why Duesday thinks so")
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(candidate.evidence.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(reasonLabel(item.reason))
                            .font(.dsBody(12))
                            .foregroundStyle(Color.dsAccentDeep)
                        Spacer()
                        Text(item.field.rawValue)
                            .font(.dsCaption(10))
                            .textCase(.uppercase)
                            .tracking(DS.tracking(0.06, size: 10))
                            .foregroundStyle(Color.dsInkTertiary)
                    }
                    Text("\u{201C}\(item.snippet)\u{201D}")
                        .font(.dsBodyItalic(12.5))
                        .foregroundStyle(Color.dsInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Color.dsDivider).frame(height: 1)
                        .padding(.top, DS.Spacing.sm)
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            Text("Only these short excerpts were kept — the full email stays in your mailbox, not in Duesday.")
                .font(.dsBody(11.5))
                .foregroundStyle(Color.dsInkTertiary)
                .padding(.top, DS.Spacing.sm)
        }
    }

    private func reasonLabel(_ reason: DetectionEvidence.Reason) -> String {
        switch reason {
        case .trustedSenderDomain: "Known sender"
        case .recurringPhrase: "Recurring language"
        case .labeledAmount: "Charged amount"
        case .explicitInterval: "Billing interval stated"
        case .explicitRenewalDate: "Date stated"
        case .repeatedReceipt: "Repeated receipts"
        case .cancellationLanguage: "Cancellation language"
        case .headerBodyAgreement: "Sender and subject agree"
        case .merchantPattern: "Sender name"
        case .documentText: "Imported document"
        case .userProvided: "You provided this"
        }
    }

    private var duplicateSubscription: Subscription? {
        guard let id = candidate.possibleDuplicateSubscriptionID else { return nil }
        var descriptor = FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func mergeSection(_ subscription: Subscription) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSCaptionLabel("Already on your ledger?")
                .padding(.top, DS.Spacing.lg)
                .accessibilityAddTraits(.isHeader)
            Text("This looks like \(subscription.merchantName) (\(subscription.money.formatted()) \(subscription.billingFrequency.displayName.lowercased())), which you already track. Merging updates its billing date from this detection instead of adding a second entry.")
                .font(.dsBody(13))
                .lineSpacing(3)
                .foregroundStyle(Color.dsInkSecondary)
            Button("Merge into existing entry") { merge(into: subscription) }
                .buttonStyle(.dsPrimary)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.sm) {
            if duplicateSubscription == nil {
                Button("Add to ledger") { confirm() }
                    .buttonStyle(.dsPrimary)
                    .disabled(!canConfirmDirectly)
            }
            Button("Edit before adding") { isPresentingEdit = true }
                .buttonStyle(.dsQuiet)
            HStack(spacing: 8) {
                Button("Ignore") { ignore() }
                    .buttonStyle(DSCompactOutlineButtonStyle())
                Button("Not a subscription") { reject() }
                    .buttonStyle(DSCompactOutlineButtonStyle(tint: .dsDanger))
            }
            if !canConfirmDirectly && duplicateSubscription == nil {
                Text("Some details are missing — use \u{201C}Edit before adding\u{201D} to complete them.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
            }
        }
    }

    private var canConfirmDirectly: Bool {
        candidate.merchantName != nil
            && candidate.amount != nil
            && candidate.currencyCode != nil
            && candidate.billingFrequency != nil
    }

    // MARK: - Prefill for edit-before-confirm

    private var prefill: SubscriptionFormModel.Prefill {
        SubscriptionFormModel.Prefill(
            merchantName: candidate.merchantName,
            amount: candidate.amount,
            currencyCode: candidate.currencyCode,
            frequency: candidate.billingFrequency,
            customInterval: candidate.customInterval,
            nextBillingDate: candidate.nextBillingDate,
            trialEndDate: candidate.trialEndDate,
            detectionSource: .gmail,
            confidence: candidate.confidenceScore
        )
    }

    // MARK: - Actions

    private var service: CandidateReviewService {
        CandidateReviewService(context: modelContext)
    }

    private func confirm() {
        do {
            if try service.confirm(candidate) != nil {
                Haptics.success()
                dismiss()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The form reports a successful save explicitly. Looking for a matching
    /// merchant here would produce a false positive when the user cancels and
    /// an older entry with that merchant already exists.
    private func resolveAfterEditIfSaved() {
        guard editWasSaved, candidate.reviewStatus == .pending else { return }
        editWasSaved = false
        do {
            try service.markEditedAndConfirmed(candidate)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func merge(into subscription: Subscription) {
        do {
            try service.merge(candidate, into: subscription)
            Haptics.success()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func ignore() {
        do {
            try service.ignore(candidate)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func reject() {
        do {
            try service.reject(candidate)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }
}
