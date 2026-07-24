import CoreModels
import DesignSystem
import FeatureDetectionReview
import Persistence
import SwiftData
import SwiftUI

/// Overview per the design spec: date kicker with monogram (opens Settings),
/// dominant serif monthly figure, then Next up / Needs attention / Lately
/// ledger sections separated by rules — no cards.
public struct OverviewView: View {
    @Query(filter: #Predicate<Subscription> { $0.archivedAt == nil })
    private var subscriptions: [Subscription]

    @Query(filter: #Predicate<DetectionCandidate> { $0.reviewStatusRaw == "pending" })
    private var pendingCandidates: [DetectionCandidate]

    private let onAddSubscription: () -> Void
    private let onOpenSettings: () -> Void

    public init(
        onAddSubscription: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.onAddSubscription = onAddSubscription
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            Group {
                if countedSubscriptions.isEmpty {
                    emptyLedger
                } else {
                    ledger
                }
            }
            .background(Color.dsPaper)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    // MARK: - Empty state (spec 1t: both paths forward)

    private var emptyLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer()
            Text("An empty ledger")
                .font(.dsTitle(34))
                .padding(.bottom, DS.Spacing.md)
            Text("Add what you pay for and Duesday will remember it — renewals, trials, and what a month truly costs. Email detection arrives in a coming update; entries you add now carry over.")
                .font(.dsBody(14.5))
                .foregroundStyle(Color.dsInkSecondary)
                .lineSpacing(4)
            Spacer()
            VStack(spacing: DS.Spacing.sm) {
                Button("Add your first entry") { onAddSubscription() }
                    .buttonStyle(.dsPrimary)
                Text("Duesday reads receipts, not your mail.\nYou review everything it finds.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, DS.Spacing.xl)
        }
        .padding(.horizontal, DS.screenMargin)
    }

    // MARK: - Ledger

    private var ledger: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                heroFigure
                    .padding(.top, DS.Spacing.lg)

                Rectangle()
                    .fill(Color.dsRule)
                    .frame(height: 1)
                    .padding(.top, DS.Spacing.lg)

                if !pendingCandidates.isEmpty {
                    reviewInboxRow
                }
                nextUpSection
                if !attentionItems.isEmpty {
                    attentionSection
                }
                if !latelyLines.isEmpty {
                    latelySection
                }
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    private var header: some View {
        HStack {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.dsCaption(10.5))
                .textCase(.uppercase)
                .tracking(DS.tracking(0.18, size: 10.5))
                .foregroundStyle(Color.dsAccentDeep)
            Spacer()
            Button {
                onOpenSettings()
            } label: {
                Text("D")
                    .font(.dsSerif(15))
                    .foregroundStyle(Color.dsInkSecondary)
                    .frame(width: 32, height: 32)
                    .overlay { Circle().stroke(Color.dsDivider, lineWidth: 1) }
                    .frame(width: DS.minTouchTarget, height: DS.minTouchTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var heroFigure: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let primary = primaryTotal {
                HeroAmount(amount: primary.total, currencyCode: primary.currencyCode)
                Text(heroSubline(primary: primary))
                    .font(.dsBody(13))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsInkSecondary)
            } else {
                Text("Add billing intervals to see monthly cost")
                    .font(.dsBody(13))
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Entry to the review inbox (design turn 03) — shown only when
    /// detections are waiting.
    private var reviewInboxRow: some View {
        NavigationLink {
            ReviewQueueView()
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.dsAccent)
                        .frame(width: 3, height: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Found in your email")
                            .font(.dsBodyStrong(14.5))
                        Text("\(pendingCandidates.count) detection\(pendingCandidates.count == 1 ? "" : "s") waiting for review")
                            .font(.dsBody(12))
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                    Spacer()
                    Text("Review ›")
                        .font(.dsBody(13))
                        .foregroundStyle(Color.dsAccentDeep)
                }
                .padding(.vertical, 11)
                Rectangle().fill(Color.dsDivider).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private var nextUpSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Next up")
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            if upcomingCharges.isEmpty {
                Text("Nothing due in the next 30 days.")
                    .font(.dsBody(13))
                    .foregroundStyle(Color.dsInkSecondary)
                    .padding(.vertical, DS.Spacing.sm)
            }
            ForEach(Array(upcomingCharges.enumerated()), id: \.offset) { _, charge in
                upcomingRow(charge)
            }
        }
    }

    private func upcomingRow(_ charge: UpcomingCharges.Charge) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DSGlyphBox(
                    for: charge.subscription.merchantName,
                    size: 36,
                    style: charge.subscription.status == .trial ? .trial : .standard
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(charge.subscription.merchantName)
                        .font(.dsBodyStrong(14.5))
                    Text(charge.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.dsBody(12))
                        .foregroundStyle(Color.dsInkSecondary)
                }
                Spacer()
                AmountText(charge.money, presentation: .row)
            }
            .padding(.vertical, 11)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Needs attention")
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(attentionItems) { item in
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.isFailure ? Color.dsDanger : Color.dsAccent)
                            .frame(width: 3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.dsBodyStrong(14))
                            Text(item.detail)
                                .font(.dsBody(12.5))
                                .monospacedDigit()
                                .foregroundStyle(Color.dsInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    Rectangle().fill(Color.dsDivider).frame(height: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var latelySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Lately")
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            ForEach(latelyLines) { line in
                Text("\(line.date, format: .dateTime.month(.abbreviated).day()) — \(line.text)")
                    .font(.dsBody(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsInk.opacity(0.72))
                    .padding(.vertical, 5)
            }
        }
    }

    // MARK: - Data

    private var countedSubscriptions: [Subscription] {
        subscriptions.filter { $0.status.countsTowardSpending }
    }

    private var monthlyTotals: [SpendingMath.CurrencyTotal] {
        SpendingMath.totalsByCurrency(
            countedSubscriptions.compactMap { subscription in
                subscription.estimatedMonthlyCost.map {
                    Money(amount: $0, currencyCode: subscription.currencyCode)
                }
            }
        )
    }

    private var primaryTotal: SpendingMath.CurrencyTotal? { monthlyTotals.first }

    private func heroSubline(primary: SpendingMath.CurrencyTotal) -> String {
        let annual = (primary.total * 12).rounded(scale: 0)
        let annualText = Money(amount: annual, currencyCode: primary.currencyCode).formatted()
        var line = "a month · about \(annualText) a year · \(countedSubscriptions.count) active"
        let others = monthlyTotals.dropFirst()
        if !others.isEmpty {
            let extras = others.map { $0.money.formatted() + "/mo" }.joined(separator: ", ")
            line += " · plus \(extras)"
        }
        return line
    }

    private var upcomingCharges: [UpcomingCharges.Charge] {
        Array(
            UpcomingCharges.charges(
                for: countedSubscriptions,
                within: UpcomingCharges.window(days: 30)
            )
            .prefix(4)
        )
    }

    private struct AttentionItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isFailure: Bool
    }

    private var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        let calendar = Calendar.current
        let now = Date.now

        for subscription in countedSubscriptions {
            // Trials about to convert (spec: "Becomes $X/mo … unless cancelled").
            if subscription.status == .trial,
               let trialEnd = subscription.trialEndDate,
               trialEnd >= now,
               let days = calendar.dateComponents([.day], from: now, to: trialEnd).day,
               days <= 30 {
                let price = subscription.regularPrice ?? subscription.amount
                let priceText = Money(amount: price, currencyCode: subscription.currencyCode).formatted()
                let when = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
                items.append(AttentionItem(
                    id: "trial-\(subscription.id)",
                    title: "\(subscription.merchantName) trial ends \(when)",
                    detail: "Becomes \(priceText)/mo on \(trialEnd.formatted(.dateTime.month(.abbreviated).day())) unless cancelled.",
                    isFailure: false
                ))
            }

            // Introductory price expiring → price increase.
            if let intro = subscription.introductoryPriceEndDate,
               intro >= now,
               let regular = subscription.regularPrice,
               regular > subscription.amount {
                let from = subscription.money.formatted()
                let to = Money(amount: regular, currencyCode: subscription.currencyCode).formatted()
                items.append(AttentionItem(
                    id: "price-\(subscription.id)",
                    title: "\(subscription.merchantName) price increase",
                    detail: "\(from) → \(to) from your \(intro.formatted(.dateTime.month(.wide))) renewal.",
                    isFailure: false
                ))
            }

            // Recent failed payments recorded on renewal events.
            for event in subscription.renewalEvents where event.status == .failed {
                let reference = event.actualDate ?? event.expectedDate
                if let days = calendar.dateComponents([.day], from: reference, to: now).day,
                   days >= 0, days <= 30 {
                    items.append(AttentionItem(
                        id: "failed-\(event.id)",
                        title: "\(subscription.merchantName) payment failed",
                        detail: "\(reference.formatted(.dateTime.month(.abbreviated).day())) charge declined. The merchant may retry — check your payment method.",
                        isFailure: true
                    ))
                }
            }
        }
        return items
    }

    private struct LatelyLine: Identifiable {
        let id: String
        let date: Date
        let text: String
    }

    private var latelyLines: [LatelyLine] {
        var lines: [LatelyLine] = []
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: .now) ?? .now

        for subscription in subscriptions {
            if subscription.createdAt >= cutoff {
                let priceText = subscription.money.formatted()
                lines.append(LatelyLine(
                    id: "added-\(subscription.id)",
                    date: subscription.createdAt,
                    text: "Added \(subscription.merchantName), \(priceText)"
                ))
            }
            for event in subscription.renewalEvents {
                guard let actual = event.actualDate, actual >= cutoff else { continue }
                switch event.status {
                case .confirmed:
                    let amount = event.actualAmount ?? subscription.amount
                    let priceText = Money(amount: amount, currencyCode: subscription.currencyCode).formatted()
                    lines.append(LatelyLine(
                        id: "renewed-\(event.id)",
                        date: actual,
                        text: "\(subscription.merchantName) renewed, \(priceText)"
                    ))
                case .refunded:
                    lines.append(LatelyLine(
                        id: "refund-\(event.id)",
                        date: actual,
                        text: "\(subscription.merchantName) refunded"
                    ))
                default:
                    break
                }
            }
        }
        return Array(lines.sorted { $0.date > $1.date }.prefix(3))
    }
}

/// The dominant serif figure with smaller fraction digits, per spec.
private struct HeroAmount: View {
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        let whole = wholePart
        let fraction = fractionPart
        return (
            Text(whole)
                .font(.dsDisplay(64))
            + Text(fraction)
                .font(.dsDisplay(34))
        )
        .monospacedDigit()
        .accessibilityLabel(Money(amount: amount, currencyCode: currencyCode).formatted())
    }

    private var wholePart: String {
        let truncated = amount.rounded(scale: 0, mode: .down)
        return Money(amount: truncated, currencyCode: currencyCode)
            .formatted()
            .replacingOccurrences(of: fractionSuffix(of: truncated), with: "")
    }

    private var fractionPart: String {
        let cents = ((amount - amount.rounded(scale: 0, mode: .down)) * 100).rounded(scale: 0)
        let value = NSDecimalNumber(decimal: cents).intValue
        return String(format: ".%02d", max(0, min(99, value)))
    }

    private func fractionSuffix(of value: Decimal) -> String {
        // Formatted whole includes ".00"-style suffix in some locales; strip it.
        let formatted = Money(amount: value, currencyCode: currencyCode).formatted()
        if let range = formatted.range(of: #"[.,]00$"#, options: .regularExpression) {
            return String(formatted[range])
        }
        return ""
    }
}
