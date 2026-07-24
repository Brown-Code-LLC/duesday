import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Review inbox per the design spec (frame 1g): pending detections with
/// selection for safe bulk confirm — only high-confidence candidates are
/// selectable in bulk, and ignore is always one tap away.
public struct ReviewQueueView: View {
    @Query(
        filter: #Predicate<DetectionCandidate> { $0.reviewStatusRaw == "pending" },
        sort: [SortDescriptor(\DetectionCandidate.detectedDate, order: .reverse)]
    )
    private var pending: [DetectionCandidate]

    @State private var selection: Set<UUID> = []
    @State private var isSelecting = false
    @State private var actionError: String?
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if pending.isEmpty {
                    emptyState
                        .padding(.top, DS.Spacing.xxl)
                } else {
                    if isSelecting {
                        bulkBar
                            .padding(.top, DS.Spacing.md)
                    }
                    ForEach(pending) { candidate in
                        NavigationLink {
                            CandidateDetailView(candidate: candidate)
                        } label: {
                            CandidateRow(
                                candidate: candidate,
                                isSelecting: isSelecting,
                                isSelected: selection.contains(candidate.id),
                                onToggleSelection: { toggleSelection(candidate) },
                                onIgnore: { ignore(candidate) }
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSelecting)
                    }
                }
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.bottom, DS.Spacing.xl)
        }
        .background(Color.dsPaper)
        .navigationTitle("Review")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Header & bulk selection

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Found in your email")
                .font(.dsTitle(26))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !pending.isEmpty {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                }
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsAccentDeep)
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var bulkEligible: [DetectionCandidate] {
        pending.filter { selection.contains($0.id) && $0.isEligibleForBulkConfirm }
    }

    private var bulkBar: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button {
                bulkConfirm()
            } label: {
                Text("Confirm \(bulkEligible.count) selected")
            }
            .buttonStyle(.dsPrimary)
            .disabled(bulkEligible.isEmpty)
            // Consequences stay visible before the action (spec: bulk
            // confirmation must show what will happen).
            Text(bulkConsequence)
                .font(.dsBody(11.5))
                .foregroundStyle(Color.dsInkTertiary)
        }
    }

    private var bulkConsequence: String {
        guard !bulkEligible.isEmpty else {
            return "Only high-confidence detections with complete details can be bulk-confirmed. Open the rest to review them individually."
        }
        let names = bulkEligible.compactMap(\.merchantName).prefix(3).joined(separator: ", ")
        let more = bulkEligible.count > 3 ? "…" : ""
        return "Adds \(names)\(more) to your ledger with default reminders. You can edit or remove them afterwards."
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("Nothing to review")
                .font(.dsTitle(24))
            Text("When email scanning finds likely subscriptions, they wait here for your say-so.")
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsInkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var service: CandidateReviewService {
        CandidateReviewService(context: modelContext)
    }

    private func toggleSelection(_ candidate: DetectionCandidate) {
        guard candidate.isEligibleForBulkConfirm else { return }
        if selection.contains(candidate.id) {
            selection.remove(candidate.id)
        } else {
            selection.insert(candidate.id)
        }
        Haptics.selection()
    }

    private func bulkConfirm() {
        do {
            let count = try service.bulkConfirm(bulkEligible)
            selection.removeAll()
            isSelecting = false
            if count > 0 { Haptics.success() }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func ignore(_ candidate: DetectionCandidate) {
        do {
            try service.ignore(candidate)
            Haptics.selection()
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

/// One pending detection: merchant, billing shape, top evidence quote,
/// confidence tag, and a one-tap Ignore.
private struct CandidateRow: View {
    let candidate: DetectionCandidate
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if isSelecting {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(
                                candidate.isEligibleForBulkConfirm
                                    ? Color.dsAccentDeep
                                    : Color.dsChipBorder
                            )
                            .frame(width: 32, height: 38)
                    }
                    .buttonStyle(.plain)
                    .disabled(!candidate.isEligibleForBulkConfirm)
                    .accessibilityLabel(isSelected ? "Deselect" : "Select")
                } else {
                    DSGlyphBox(for: candidate.merchantName ?? "?", size: 38)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.merchantName ?? "Unknown merchant")
                            .font(.dsBodyStrong(14.5))
                            .lineLimit(1)
                        confidenceTag
                        if candidate.possibleDuplicateSubscriptionID != nil {
                            DSTagPill("Maybe existing", style: .neutral)
                        }
                    }
                    Text(billingLine)
                        .font(.dsBody(12))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkSecondary)
                    if let quote = candidate.evidence.first?.snippet, !quote.isEmpty {
                        Text("\u{201C}\(quote)\u{201D}")
                            .font(.dsBodyItalic(11.5))
                            .foregroundStyle(Color.dsInkTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: DS.Spacing.sm)
                if !isSelecting {
                    Button("Ignore", action: onIgnore)
                        .font(.dsBody(12.5))
                        .foregroundStyle(Color.dsInkSecondary)
                        .frame(minHeight: DS.minTouchTarget)
                        .accessibilityHint("Removes this detection without adding it")
                }
            }
            .padding(.vertical, 11)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var billingLine: String {
        var parts: [String] = []
        if let amount = candidate.amount, let currency = candidate.currencyCode {
            parts.append(Money(amount: amount, currencyCode: currency).formatted())
        }
        if let frequency = candidate.billingFrequency {
            parts.append(frequency.displayName.lowercased())
        }
        if let trialEnd = candidate.trialEndDate {
            parts.append("trial ends \(trialEnd.formatted(.dateTime.month(.abbreviated).day()))")
        } else if let next = candidate.nextBillingDate {
            parts.append("next \(next.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return parts.isEmpty ? "Details incomplete — open to review" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var confidenceTag: some View {
        if candidate.confidenceScore >= DetectionCandidate.bulkConfirmThreshold {
            DSTagPill("Likely", style: .accent)
        } else if candidate.confidenceScore >= 0.5 {
            DSTagPill("Possible", style: .neutral)
        } else {
            DSTagPill("Uncertain", style: .neutral)
        }
    }
}
