import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Full subscription record per the design spec: monogram + serif title with
/// status pills, big serif price, hairline key-value table, price history,
/// cancellation guidance with domain-disclosed links, compact action row.
public struct SubscriptionDetailView: View {
    @Bindable var subscription: Subscription
    @State private var isPresentingEdit = false
    @State private var isPresentingReminders = false
    @State private var isConfirmingDelete = false
    @State private var pendingLink: URL?
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.subscriptionRepository) private var injectedRepository
    @Environment(\.openURL) private var openURL

    public init(subscription: Subscription) {
        self.subscription = subscription
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                identityHeader
                    .padding(.top, DS.Spacing.xs)
                priceLine
                    .padding(.top, DS.Spacing.lg)
                recordTable
                    .padding(.top, DS.Spacing.md)
                if !priceHistory.isEmpty {
                    historySection
                }
                cancellingSection
                actionRow
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)
            }
            .padding(.horizontal, DS.screenMargin)
        }
        .background(Color.dsPaper)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $isPresentingEdit) {
            SubscriptionFormView(mode: .edit(subscription))
        }
        .sheet(isPresented: $isPresentingReminders) {
            ReminderRulesSheet(subscription: subscription) { persistChange() }
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Open link?",
            isPresented: linkDialogBinding,
            titleVisibility: .visible
        ) {
            if let url = pendingLink {
                Button("Open \(url.host() ?? "link")") {
                    openURL(url)
                    pendingLink = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingLink = nil }
        } message: {
            // Domain disclosure before leaving the app (privacy model, rule 4).
            Text("This opens \(pendingLink?.host() ?? "an external site") in your browser.")
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSubscription() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the entry and its reminders. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.dsInkSecondary)
                    .frame(width: DS.minTouchTarget, height: DS.minTouchTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            Button("Edit") { isPresentingEdit = true }
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsAccentDeep)
                .frame(minHeight: DS.minTouchTarget)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            DSGlyphBox(
                for: subscription.merchantName,
                size: 54,
                style: subscription.status == .trial ? .trial : .standard
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(subscription.merchantName)
                    .font(.dsTitle(28))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    subscription.status.badge
                    DSTagPill(subscription.ownershipType.displayName, capsule: true)
                }
            }
            Spacer()
        }
    }

    private var priceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(subscription.money.formatted())
                .font(.dsDisplay(42))
                .monospacedDigit()
            Text(priceSubline)
                .font(.dsBody(13))
                .monospacedDigit()
                .foregroundStyle(Color.dsInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var priceSubline: String {
        var parts = [cadenceLong]
        if let annual = subscription.estimatedAnnualCost,
           subscription.billingFrequency != .annual {
            let annualText = Money(amount: annual, currencyCode: subscription.currencyCode).formatted()
            parts.append("\(annualText) a year")
        }
        return parts.joined(separator: " · ")
    }

    private var cadenceLong: String {
        switch subscription.billingFrequency {
        case .weekly: "a week"
        case .monthly: "a month"
        case .quarterly: "a quarter"
        case .semiannual: "every 6 months"
        case .annual: "a year"
        case .custom:
            subscription.customInterval.map {
                "every \($0.count) \($0.unit.rawValue)\($0.count > 1 ? "s" : "")"
            } ?? "custom schedule"
        }
    }

    // MARK: - Record table

    private var recordTable: some View {
        VStack(spacing: 0) {
            if let next = subscription.nextBillingDate {
                DSLedgerRow(
                    "Next charge",
                    value: next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    topRule: true
                )
            }
            if let trialEnd = subscription.trialEndDate {
                DSLedgerRow("Trial ends", topRule: subscription.nextBillingDate == nil) {
                    Text(trialEnd.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .foregroundStyle(Color.dsAccentDeep)
                }
            }
            if let plan = subscription.planName {
                DSLedgerRow("Plan", value: plan)
            }
            if let payment = subscription.paymentMethodLabel {
                DSLedgerRow("Payment method", value: payment)
            }
            DSLedgerRow("Category", value: subscription.category.displayName)
            if let sinceText {
                DSLedgerRow("Since", value: sinceText)
            }
            Button {
                isPresentingReminders = true
            } label: {
                DSLedgerRow("Reminder") {
                    Text("\(reminderSummary) ›")
                        .foregroundStyle(Color.dsAccentDeep)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Configure reminders for this entry")
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .font(.dsBody(13.5))
    }

    private var sinceText: String? {
        guard let start = subscription.startDate else { return nil }
        var text = start.formatted(.dateTime.month(.wide).year())
        let renewals = subscription.renewalEvents.count(where: { $0.status == .confirmed })
        if renewals > 0 {
            text += " · \(renewals) renewal\(renewals == 1 ? "" : "s")"
        }
        return text
    }

    private var reminderSummary: String {
        let enabled = subscription.reminderRules.filter(\.isEnabled)
        guard !enabled.isEmpty else { return "Off" }
        if let before = enabled.first(where: { $0.reminderType == .beforeBilling }) {
            return before.leadTimeDays == 1 ? "1 day before" : "\(before.leadTimeDays) days before"
        }
        if enabled.contains(where: { $0.reminderType == .billingDay }) { return "On the day" }
        if enabled.contains(where: { $0.reminderType == .trialEnd }) { return "Trial end" }
        return "\(enabled.count) set"
    }

    // MARK: - Price history

    private struct HistoryEntry: Identifiable {
        let id: UUID
        let date: Date
        let text: String
        let deltaText: String?
        let isRecent: Bool
    }

    private var priceHistory: [HistoryEntry] {
        let confirmed = subscription.renewalEvents
            .filter { $0.status == .confirmed && $0.actualAmount != nil }
            .sorted { ($0.actualDate ?? $0.expectedDate) < ($1.actualDate ?? $1.expectedDate) }

        var entries: [HistoryEntry] = []
        var previous: Decimal?
        for event in confirmed {
            guard let amount = event.actualAmount else { continue }
            if let previous, amount != previous {
                let date = event.actualDate ?? event.expectedDate
                let delta = amount - previous
                let money = Money(amount: amount, currencyCode: subscription.currencyCode)
                let deltaMoney = Money(amount: abs(delta), currencyCode: subscription.currencyCode)
                entries.append(HistoryEntry(
                    id: event.id,
                    date: date,
                    text: "\(date.formatted(.dateTime.month(.abbreviated).year())) — \(delta > 0 ? "raised" : "lowered") to \(money.formatted())",
                    deltaText: (delta > 0 ? "+" : "−") + deltaMoney.formatted(),
                    isRecent: false
                ))
            }
            previous = amount
        }
        // Most recent change first, gold-highlighted.
        var reversed = Array(entries.reversed())
        if !reversed.isEmpty {
            reversed[0] = HistoryEntry(
                id: reversed[0].id,
                date: reversed[0].date,
                text: reversed[0].text,
                deltaText: reversed[0].deltaText,
                isRecent: true
            )
        }
        return reversed
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Price history")
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(priceHistory) { entry in
                VStack(spacing: 0) {
                    HStack {
                        Text(entry.text)
                            .font(.dsBody(13))
                            .monospacedDigit()
                            .foregroundStyle(entry.isRecent ? Color.dsInk : Color.dsInkSecondary)
                        Spacer()
                        if let delta = entry.deltaText {
                            Text(delta)
                                .font(.dsBody(13))
                                .monospacedDigit()
                                .foregroundStyle(entry.isRecent ? Color.dsAccentDeep : Color.dsInkTertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    Rectangle().fill(Color.dsDivider).frame(height: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Cancelling

    @ViewBuilder
    private var cancellingSection: some View {
        if subscription.cancellationInstructions != nil
            || subscription.cancellationURL != nil
            || subscription.websiteURL != nil {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSCaptionLabel("Cancelling")
                    .padding(.top, DS.Spacing.lg)
                    .accessibilityAddTraits(.isHeader)
                if let instructions = subscription.cancellationInstructions {
                    Text(instructions)
                        .font(.dsBody(13))
                        .lineSpacing(4)
                        .foregroundStyle(Color.dsInk.opacity(0.75))
                }
                if let url = subscription.cancellationURL {
                    linkButton(title: url.host() ?? "Cancellation page", url: url)
                }
                if let url = subscription.websiteURL, url != subscription.cancellationURL {
                    linkButton(title: url.host() ?? "Website", url: url)
                }
            }
        }
    }

    private func linkButton(title: String, url: URL) -> some View {
        Button {
            pendingLink = url
        } label: {
            Text(title)
                .font(.dsBody(13))
                .foregroundStyle(Color.dsAccentDeep)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.dsAccentSoft).frame(height: 1).offset(y: 2)
                }
                .frame(minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the destination before opening in your browser")
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            if subscription.status == .canceled {
                Button("Mark active") { setStatus(.active) }
                    .buttonStyle(DSCompactOutlineButtonStyle())
            } else {
                Button("Mark cancelled") { setStatus(.canceled) }
                    .buttonStyle(DSCompactOutlineButtonStyle())
            }
            if subscription.isArchived {
                Button("Unarchive") { unarchive() }
                    .buttonStyle(DSCompactOutlineButtonStyle())
            } else {
                Button("Archive") { archive() }
                    .buttonStyle(DSCompactOutlineButtonStyle())
            }
            Button("Delete") { isConfirmingDelete = true }
                .buttonStyle(DSCompactOutlineButtonStyle(tint: .dsDanger))
        }
    }

    // MARK: - Plumbing

    private var repository: any SubscriptionRepository {
        injectedRepository ?? SwiftDataSubscriptionRepository(context: modelContext)
    }

    private var linkDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingLink != nil },
            set: { if !$0 { pendingLink = nil } }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }

    private func setStatus(_ status: SubscriptionStatus) {
        subscription.status = status
        persistChange()
        Haptics.success()
    }

    private func persistChange() {
        subscription.updatedAt = .now
        do {
            try repository.save()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func archive() {
        do {
            try repository.archive(subscription)
            Haptics.success()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unarchive() {
        do {
            try repository.unarchive(subscription)
            Haptics.success()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteSubscription() {
        do {
            try repository.delete(subscription)
            Haptics.success()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Reminder rules sheet

/// Per-entry reminder configuration, presented from the record's Reminder row.
private struct ReminderRulesSheet: View {
    @Bindable var subscription: Subscription
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedRules) { rule in
                        ReminderRuleRow(rule: rule, onChange: onChange) {
                            removeRule(rule)
                        }
                    }
                    if sortedRules.isEmpty {
                        Text("No reminders set for this entry.")
                            .font(.dsBody(13.5))
                            .foregroundStyle(Color.dsInkSecondary)
                            .padding(.vertical, DS.Spacing.lg)
                    }
                    addSection
                        .padding(.top, DS.Spacing.lg)
                }
                .padding(.horizontal, DS.screenMargin)
                .padding(.top, DS.Spacing.md)
            }
            .background(Color.dsPaper)
            .navigationTitle("Reminders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sortedRules: [ReminderRule] {
        subscription.reminderRules.sorted { lhs, rhs in
            if lhs.leadTimeDays != rhs.leadTimeDays { return lhs.leadTimeDays < rhs.leadTimeDays }
            return lhs.reminderTypeRaw < rhs.reminderTypeRaw
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSCaptionLabel("Add")
            FlowChips(options: availablePresets.map(\.title)) { title in
                if let preset = availablePresets.first(where: { $0.title == title }) {
                    addRule(preset)
                }
            }
        }
    }

    private struct Preset {
        let title: String
        let type: ReminderType
        let leadDays: Int
    }

    private var availablePresets: [Preset] {
        var presets: [Preset] = ReminderRule.standardLeadTimesDays
            .filter { lead in
                !subscription.reminderRules.contains {
                    $0.reminderType != .trialEnd && $0.leadTimeDays == lead
                }
            }
            .map { lead in
                switch lead {
                case 0: Preset(title: "On the day", type: .billingDay, leadDays: 0)
                case 1: Preset(title: "1 day before", type: .beforeBilling, leadDays: 1)
                default: Preset(title: "\(lead) days before", type: .beforeBilling, leadDays: lead)
                }
            }
        if subscription.trialEndDate != nil,
           !subscription.reminderRules.contains(where: { $0.reminderType == .trialEnd }) {
            presets.append(Preset(title: "When the trial ends", type: .trialEnd, leadDays: 1))
        }
        return presets
    }

    private func addRule(_ preset: Preset) {
        subscription.reminderRules.append(
            ReminderRule(reminderType: preset.type, leadTimeDays: preset.leadDays)
        )
        onChange()
        Haptics.selection()
    }

    private func removeRule(_ rule: ReminderRule) {
        subscription.reminderRules.removeAll { $0.id == rule.id }
        modelContext.delete(rule)
        onChange()
    }
}

/// One reminder rule row: enable toggle plus a plain-language description.
private struct ReminderRuleRow: View {
    @Bindable var rule: ReminderRule
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                Toggle(isOn: $rule.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.dsBody(14))
                        Text("at \(timeText)")
                            .font(.dsBody(12))
                            .foregroundStyle(Color.dsInkTertiary)
                    }
                }
                .tint(.dsAccent)
                .onChange(of: rule.isEnabled) { onChange() }
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsInkTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }
            .padding(.vertical, 9)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    private var title: String {
        switch rule.reminderType {
        case .billingDay: "On the billing day"
        case .beforeBilling:
            rule.leadTimeDays == 1 ? "1 day before billing" : "\(rule.leadTimeDays) days before billing"
        case .trialEnd:
            rule.leadTimeDays == 0 ? "When the trial ends" : "\(rule.leadTimeDays) day(s) before the trial ends"
        case .priceIncrease: "On price increases"
        case .paymentFailed: "On failed payments"
        case .syncFailure: "On sync problems"
        }
    }

    private var timeText: String {
        var components = DateComponents()
        components.hour = rule.timeOfDayMinutes / 60
        components.minute = rule.timeOfDayMinutes % 60
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Simple wrapping chip group used for reminder presets.
private struct FlowChips: View {
    let options: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                DSFilterChip(option, isSelected: false) { onTap(option) }
            }
        }
    }
}
