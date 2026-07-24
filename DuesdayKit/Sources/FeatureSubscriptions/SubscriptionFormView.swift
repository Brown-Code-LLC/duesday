import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// New entry / edit form per the design spec: boxed fields with uppercase
/// labels, a segmented "Billed" control with a live "≈ … a month on your
/// ledger" line, ledger rows for organizing fields, an introductory-price
/// disclosure, and progressive disclosure for trial/notes/links.
public struct SubscriptionFormView: View {
    @State private var model: SubscriptionFormModel
    @State private var saveError: String?
    @State private var showsMore = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.subscriptionRepository) private var injectedRepository
    @FocusState private var focusedField: Field?
    private let onSaved: () -> Void

    private enum Field {
        case merchant, amount, regularPrice, plan, payment, website, cancellation, instructions, notes
    }

    public init(
        mode: SubscriptionFormModel.Mode = .create,
        onSaved: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: SubscriptionFormModel(mode: mode))
        self.onSaved = onSaved
    }

    /// Seeds the form with detected values (review workflow's
    /// edit-before-confirm path).
    public init(
        mode: SubscriptionFormModel.Mode = .create,
        prefill: SubscriptionFormModel.Prefill,
        onSaved: @escaping () -> Void = {}
    ) {
        let model = SubscriptionFormModel(mode: mode)
        model.apply(prefill)
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    labeledBox("Merchant") {
                        TextField("Netflix, Con Edison, the gym…", text: $model.merchantName)
                            .font(.dsBody(16))
                            .focused($focusedField, equals: .merchant)
                            .textContentType(.organizationName)
                    }

                    HStack(spacing: 10) {
                        labeledBox("Amount") {
                            TextField("0.00", value: $model.amount, format: .number)
                                .font(.dsSerif(19))
                                .monospacedDigit()
                                .focused($focusedField, equals: .amount)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .accessibilityLabel("Billing amount")
                        }
                        .frame(maxWidth: .infinity)
                        labeledBox("Currency") {
                            Menu {
                                ForEach(CurrencyCatalog.ordered(), id: \.self) { code in
                                    Button(CurrencyCatalog.displayName(for: code)) {
                                        model.currencyCode = code
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(model.currencyCode)
                                        .font(.dsBody(15))
                                        .foregroundStyle(Color.dsInk)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.dsInkTertiary)
                                }
                            }
                            .accessibilityLabel("Currency, \(model.currencyCode)")
                        }
                        .frame(width: 132)
                    }

                    billedSection
                    nextPaymentSection
                    organizeRows
                    introPriceSection
                    moreSection

                    if let message = saveError ?? model.validationError?.errorDescription,
                       saveError != nil || model.amount != nil || !model.merchantName.isEmpty {
                        Text(message)
                            .font(.dsBody(12.5))
                            .foregroundStyle(Color.dsDanger)
                            .padding(.top, DS.Spacing.xs)
                    }
                }
                .padding(.horizontal, DS.screenMargin)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .background(Color.dsPaper)
            .navigationTitle(model.isEditing ? "Edit entry" : "New entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.dsInkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(Color.dsAccentDeep)
                        .disabled(!model.canSave)
                }
            }
        }
    }

    // MARK: - Billed

    private static let frequencySegments: [(BillingFrequency, String)] = [
        (.weekly, "Weekly"), (.monthly, "Monthly"), (.quarterly, "Quarterly"),
        (.semiannual, "6-mo"), (.annual, "Yearly"), (.custom, "Custom"),
    ]

    private var billedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Billed")
            HStack(spacing: 0) {
                ForEach(Array(Self.frequencySegments.enumerated()), id: \.offset) { index, segment in
                    let (frequency, label) = segment
                    let selected = model.frequency == frequency
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { model.frequency = frequency }
                        Haptics.selection()
                    } label: {
                        Text(label)
                            .font(.dsBody(12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? Color.dsAccentDeep : Color.dsInkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(selected ? Color.dsAccentWash : Color.dsField)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle().fill(Color.dsDivider).frame(width: 1)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.field)
                    .stroke(Color.dsDivider, lineWidth: 1)
            }

            if model.frequency == .custom {
                HStack(spacing: DS.Spacing.md) {
                    Stepper(value: $model.customCount, in: 1...365) {
                        Text("Every \(model.customCount)")
                            .font(.dsBody(14))
                    }
                    .accessibilityLabel("Custom interval count")
                    Menu {
                        ForEach(CustomInterval.Unit.allCases) { unit in
                            Button(unit.displayName) { model.customUnit = unit }
                        }
                    } label: {
                        Text(model.customUnit.displayName)
                            .font(.dsBody(14))
                            .foregroundStyle(Color.dsAccentDeep)
                    }
                }
                .padding(.top, 2)
            }

            if let estimate = monthlyEstimateLine {
                Text(estimate)
                    .font(.dsBody(12))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
    }

    private var monthlyEstimateLine: String? {
        guard let amount = model.amount, amount > 0,
              model.frequency != .monthly,
              let monthly = SpendingMath.monthlyEstimate(
                amount: amount,
                frequency: model.frequency,
                customInterval: model.frequency == .custom
                    ? CustomInterval(count: model.customCount, unit: model.customUnit)
                    : nil
              )
        else { return nil }
        let money = Money(amount: monthly, currencyCode: model.currencyCode)
        return "≈ \(money.formatted()) a month on your ledger"
    }

    // MARK: - Dates

    private var nextPaymentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Next payment")
            HStack {
                Toggle("Known date", isOn: $model.hasNextBillingDate.animation())
                    .font(.dsBody(14))
                    .tint(.dsAccent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.dsField, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.field)
                    .stroke(Color.dsDivider, lineWidth: 1)
            }
            if model.hasNextBillingDate {
                DatePicker(
                    "Next payment date",
                    selection: $model.nextBillingDate,
                    displayedComponents: .date
                )
                .font(.dsBody(14))
                .tint(.dsAccentDeep)
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
    }

    // MARK: - Organize rows

    private var organizeRows: some View {
        VStack(spacing: 0) {
            menuLedgerRow("Category", value: model.category.displayName, topRule: true) {
                ForEach(SubscriptionCategory.allCases) { category in
                    Button(category.displayName) { model.category = category }
                }
            }
            menuLedgerRow("Label", value: model.ownership.displayName) {
                ForEach(OwnershipType.allCases) { ownership in
                    Button(ownership.displayName) { model.ownership = ownership }
                }
            }
            menuLedgerRow("Status", value: model.status.displayName) {
                ForEach(SubscriptionStatus.allCases) { status in
                    Button(status.displayName) { model.status = status }
                }
            }
            VStack(spacing: 0) {
                Rectangle().fill(Color.dsDivider).frame(height: 1)
                HStack {
                    Text("Payment method")
                        .font(.dsBody(14))
                    Spacer()
                    TextField("Visa ···4821", text: $model.paymentMethodLabel)
                        .font(.dsBody(14))
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .payment)
                        .frame(maxWidth: 160)
                }
                .padding(.vertical, 10)
                Rectangle().fill(Color.dsDivider).frame(height: 1)
            }
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func menuLedgerRow(
        _ label: String,
        value: String,
        topRule: Bool = false,
        @ViewBuilder options: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(topRule ? Color.dsRule : Color.dsDivider)
                .frame(height: 1)
            Menu {
                options()
            } label: {
                HStack {
                    Text(label)
                        .font(.dsBody(14))
                        .foregroundStyle(Color.dsInk)
                    Spacer()
                    Text("\(value) ›")
                        .font(.dsBody(14))
                        .foregroundStyle(Color.dsInkSecondary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(label), \(value)")
        }
    }

    // MARK: - Introductory price

    private var introPriceSection: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Introductory price?")
                        .font(.dsBody(14))
                    Text("Set a later price and the date it changes")
                        .font(.dsBody(12))
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Spacer()
                Toggle("", isOn: $model.hasIntroPricing.animation())
                    .labelsHidden()
                    .tint(.dsAccent)
                    .accessibilityLabel("Introductory price")
            }
            .padding(.vertical, 8)
            if model.hasIntroPricing {
                HStack(spacing: 10) {
                    labeledBox("Later price") {
                        TextField("0.00", value: $model.regularPrice, format: .number)
                            .font(.dsSerif(17))
                            .monospacedDigit()
                            .focused($focusedField, equals: .regularPrice)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Changes on")
                        DatePicker("Price change date", selection: $model.introEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(.dsAccentDeep)
                    }
                }
                .padding(.bottom, DS.Spacing.sm)
            }
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    // MARK: - Progressive disclosure

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !showsMore {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsMore = true }
                } label: {
                    Text("+ Trial end date · plan · notes · cancellation link")
                        .font(.dsBody(13.5))
                        .foregroundStyle(Color.dsInkSecondary)
                        .frame(minHeight: DS.minTouchTarget, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                labeledBox("Plan (optional)") {
                    TextField("Standard, 1080p", text: $model.planName)
                        .font(.dsBody(15))
                        .focused($focusedField, equals: .plan)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Free trial ends", isOn: $model.hasTrialEnd.animation())
                        .font(.dsBody(14))
                        .tint(.dsAccent)
                    if model.hasTrialEnd {
                        DatePicker("Trial end date", selection: $model.trialEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(.dsAccentDeep)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Started on", isOn: $model.hasStartDate.animation())
                        .font(.dsBody(14))
                        .tint(.dsAccent)
                    if model.hasStartDate {
                        DatePicker("Start date", selection: $model.startDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(.dsAccentDeep)
                    }
                }
                labeledBox("Cancellation link") {
                    TextField("https://…", text: $model.cancellationURLText)
                        .font(.dsBody(14))
                        .focused($focusedField, equals: .cancellation)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }
                labeledBox("How to cancel") {
                    TextField("Account › Membership › Cancel", text: $model.cancellationInstructions, axis: .vertical)
                        .font(.dsBody(14))
                        .focused($focusedField, equals: .instructions)
                        .lineLimit(2...4)
                }
                labeledBox("Website") {
                    TextField("https://…", text: $model.websiteURLText)
                        .font(.dsBody(14))
                        .focused($focusedField, equals: .website)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }
                labeledBox("Notes") {
                    TextField("Anything worth remembering", text: $model.notes, axis: .vertical)
                        .font(.dsBody(14))
                        .focused($focusedField, equals: .notes)
                        .lineLimit(2...6)
                }
            }
        }
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: - Field chrome

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption(11))
            .textCase(.uppercase)
            .tracking(DS.tracking(0.12, size: 11))
            .foregroundStyle(Color.dsInkSecondary)
    }

    private func labeledBox(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            HStack {
                content()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.dsField, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.field)
                    .stroke(Color.dsDivider, lineWidth: 1)
            }
        }
    }

    private func save() {
        let repository = injectedRepository
            ?? SwiftDataSubscriptionRepository(context: modelContext)
        do {
            try model.save(using: repository)
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            Haptics.warning()
        }
    }
}

#Preview {
    SubscriptionFormView()
        .modelContainer(for: Subscription.self, inMemory: true)
}
