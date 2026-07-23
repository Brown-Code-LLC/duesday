import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Insights per the design spec: trailing-12-month trend of outlined bars
/// (current month stroked gold), per-category monthly bars, and a
/// "Worth a look" section framing savings as the user's choice. Everything is
/// derived from recorded data — nothing invented.
public struct InsightsView: View {
    @Query(filter: #Predicate<Subscription> { $0.archivedAt == nil })
    private var subscriptions: [Subscription]

    private var calendar: Calendar { .current }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Insights")
                        .font(.dsTitle(30))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, DS.Spacing.sm)

                    if countedSubscriptions.isEmpty {
                        emptyState
                            .padding(.top, DS.Spacing.xxl)
                    } else {
                        trendSection
                        categorySection
                        if !suggestions.isEmpty {
                            worthALookSection
                        }
                    }
                }
                .padding(.horizontal, DS.screenMargin)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(Color.dsPaper)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("Nothing to weigh yet")
                .font(.dsTitle(24))
            Text("Insights appear once your ledger has active entries with amounts.")
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsInkSecondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Trend

    private struct MonthBucket: Identifiable {
        let id: Date
        let label: Date
        let total: Decimal
        let isCurrent: Bool
        let isRecorded: Bool
    }

    /// Recorded spend per month from confirmed renewals; the current month is
    /// the projected estimate (labeled as such).
    private var trendBuckets: [MonthBucket] {
        guard let primaryCurrency else { return [] }
        var buckets: [MonthBucket] = []
        for offset in stride(from: 11, through: 1, by: -1) {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: .now),
                  let interval = calendar.dateInterval(of: .month, for: monthDate)
            else { continue }
            var total = Decimal.zero
            var hasRecords = false
            for subscription in subscriptions where subscription.currencyCode == primaryCurrency {
                for event in subscription.renewalEvents where event.status == .confirmed {
                    let date = event.actualDate ?? event.expectedDate
                    if interval.contains(date), let amount = event.actualAmount ?? event.expectedAmount {
                        total += amount
                        hasRecords = true
                    }
                }
            }
            buckets.append(MonthBucket(
                id: interval.start,
                label: interval.start,
                total: total.rounded(scale: 0),
                isCurrent: false,
                isRecorded: hasRecords
            ))
        }
        // Current month: projected from monthly estimates.
        let projected = countedSubscriptions
            .filter { $0.currencyCode == primaryCurrency }
            .compactMap(\.estimatedMonthlyCost)
            .reduce(Decimal.zero, +)
        if let currentStart = calendar.dateInterval(of: .month, for: .now)?.start {
            buckets.append(MonthBucket(
                id: currentStart,
                label: currentStart,
                total: projected.rounded(scale: 0),
                isCurrent: true,
                isRecorded: true
            ))
        }
        return buckets
    }

    private var recordedBucketCount: Int {
        trendBuckets.count(where: { $0.isRecorded && !$0.isCurrent })
    }

    @ViewBuilder
    private var trendSection: some View {
        let buckets = trendBuckets
        let maxTotal = buckets.map(\.total).max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Text("Trailing 12 months")
                .font(.dsBody(12.5))
                .foregroundStyle(Color.dsInkSecondary)
                .padding(.top, 4)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(buckets) { bucket in
                    let fraction = maxTotal > 0
                        ? (bucket.total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
                        : 0
                    UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1)
                        .stroke(bucket.isCurrent ? Color.dsAccent : Color.dsInk.opacity(0.35), lineWidth: 1)
                        .background(
                            bucket.isCurrent ? Color.dsAccentWash : Color.clear
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, 74 * fraction))
                        .accessibilityLabel(trendAccessibility(bucket))
                }
            }
            .frame(height: 78, alignment: .bottom)
            .padding(.top, DS.Spacing.md)

            Rectangle().fill(Color.dsRule).frame(height: 1)

            HStack {
                if let first = buckets.first {
                    Text(axisLabel(first))
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Spacer()
                if let last = buckets.last {
                    Text(axisLabel(last))
                        .foregroundStyle(Color.dsAccentDeep)
                }
            }
            .font(.dsBody(10))
            .monospacedDigit()
            .padding(.top, 5)

            if recordedBucketCount < 2 {
                Text("The trend fills in as renewals are recorded month by month. This month shows your projected total.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
                    .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private func axisLabel(_ bucket: MonthBucket) -> String {
        let month = bucket.label.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        guard bucket.total > 0, let primaryCurrency else { return month }
        let money = Money(amount: bucket.total, currencyCode: primaryCurrency)
        return "\(month) · \(money.formatted())\(bucket.isCurrent ? " projected" : "")"
    }

    private func trendAccessibility(_ bucket: MonthBucket) -> String {
        let month = bucket.label.formatted(.dateTime.month(.wide).year())
        guard let primaryCurrency else { return month }
        let money = Money(amount: bucket.total, currencyCode: primaryCurrency)
        return "\(month), \(bucket.isCurrent ? "projected " : "")\(money.formatted())"
    }

    // MARK: - Categories

    private var countedSubscriptions: [Subscription] {
        subscriptions.filter { $0.status.countsTowardSpending }
    }

    private var primaryCurrency: String? {
        SpendingMath.totalsByCurrency(
            countedSubscriptions.compactMap { sub in
                sub.estimatedMonthlyCost.map { Money(amount: $0, currencyCode: sub.currencyCode) }
            }
        ).first?.currencyCode
    }

    private struct CategoryEntry: Identifiable {
        let id: SubscriptionCategory
        let monthly: Decimal
        let fraction: Double
    }

    private func categoryEntries(for currency: String) -> [CategoryEntry] {
        let members = countedSubscriptions.filter {
            $0.currencyCode == currency && $0.estimatedMonthlyCost != nil
        }
        let byCategory = Dictionary(grouping: members, by: \.category)
        let totals = byCategory.mapValues { subs in
            subs.compactMap(\.estimatedMonthlyCost).reduce(Decimal.zero, +).rounded(scale: 2)
        }
        let maxTotal = totals.values.max() ?? 0
        return totals
            .map { category, total in
                CategoryEntry(
                    id: category,
                    monthly: total,
                    fraction: maxTotal > 0
                        ? (total as NSDecimalNumber).doubleValue / (maxTotal as NSDecimalNumber).doubleValue
                        : 0
                )
            }
            .sorted { $0.monthly > $1.monthly }
    }

    @ViewBuilder
    private var categorySection: some View {
        if let currency = primaryCurrency {
            let entries = categoryEntries(for: currency)
            VStack(alignment: .leading, spacing: 0) {
                DSCaptionLabel("By category, monthly")
                    .padding(.top, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.id.displayName)
                                .font(.dsBody(13))
                            Spacer()
                            Text(Money(amount: entry.monthly, currencyCode: currency).formatted())
                                .font(.dsBody(13))
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.dsInk.opacity(0.1))
                                Rectangle()
                                    .fill(Color.dsAccent)
                                    .frame(width: proxy.size.width * entry.fraction)
                            }
                        }
                        .frame(height: 3)
                        Rectangle().fill(Color.dsDivider).frame(height: 1)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
                if secondaryCurrencyNote != nil {
                    Text(secondaryCurrencyNote ?? "")
                        .font(.dsBody(11.5))
                        .foregroundStyle(Color.dsInkTertiary)
                        .padding(.top, DS.Spacing.xs)
                }
            }
        }
    }

    private var secondaryCurrencyNote: String? {
        let others = SpendingMath.totalsByCurrency(
            countedSubscriptions.compactMap { sub in
                sub.estimatedMonthlyCost.map { Money(amount: $0, currencyCode: sub.currencyCode) }
            }
        ).dropFirst()
        guard !others.isEmpty else { return nil }
        let text = others.map { "\($0.money.formatted())/mo" }.joined(separator: ", ")
        return "Held separately: \(text) — currencies are never merged."
    }

    // MARK: - Worth a look

    private struct Suggestion: Identifiable {
        let id: String
        let title: String
        let detail: String
        let annualSaving: Decimal?
    }

    private var suggestions: [Suggestion] {
        var results: [Suggestion] = []
        guard let currency = primaryCurrency else { return results }

        // Overlapping services: two or more active entries in the same
        // category — keeping only the largest would save the rest.
        let overlapCategories: Set<SubscriptionCategory> = [.streaming, .music, .news, .fitness]
        let byCategory = Dictionary(
            grouping: countedSubscriptions.filter {
                $0.currencyCode == currency && $0.status == .active
            },
            by: \.category
        )
        for (category, members) in byCategory
        where overlapCategories.contains(category) && members.count >= 2 {
            let sorted = members.sorted {
                ($0.estimatedMonthlyCost ?? 0) > ($1.estimatedMonthlyCost ?? 0)
            }
            let names = sorted.map(\.merchantName).joined(separator: " and ")
            let saveable = sorted.dropFirst()
                .compactMap(\.estimatedAnnualCost)
                .reduce(Decimal.zero, +).rounded(scale: 0)
            guard saveable > 0 else { continue }
            let saveText = Money(amount: saveable, currencyCode: currency).formatted()
            results.append(Suggestion(
                id: "overlap-\(category.rawValue)",
                title: "Two \(category.displayName.lowercased()) services?",
                detail: "\(names) overlap. Keeping one saves up to \(saveText) a year.",
                annualSaving: saveable
            ))
        }

        // Trials about to convert: cancelling before the date is a choice.
        for subscription in countedSubscriptions where subscription.status == .trial {
            guard let end = subscription.trialEndDate, end >= .now,
                  subscription.currencyCode == currency else { continue }
            let becomes = subscription.regularPrice ?? subscription.amount
            guard becomes > 0,
                  let annual = SpendingMath.annualEstimate(
                    amount: becomes,
                    frequency: subscription.billingFrequency,
                    customInterval: subscription.customInterval
                  ) else { continue }
            let annualText = Money(amount: annual.rounded(scale: 0), currencyCode: currency).formatted()
            results.append(Suggestion(
                id: "trial-\(subscription.id)",
                title: "\(subscription.merchantName) trial decision",
                detail: "Converts \(end.formatted(.dateTime.month(.abbreviated).day())). Letting it lapse saves \(annualText) a year.",
                annualSaving: annual.rounded(scale: 0)
            ))
        }
        return results
    }

    private var worthALookSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCaptionLabel("Worth a look")
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.dsBodyStrong(14))
                    Text(suggestion.detail)
                        .font(.dsBody(12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Color.dsDivider).frame(height: 1)
                        .padding(.top, DS.Spacing.sm)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            if let combined = combinedSavings {
                HStack(alignment: .firstTextBaseline) {
                    Text("If you act on all of these")
                        .font(.dsBodyStrong(14))
                    Spacer()
                    Text(combined)
                        .font(.dsSerif(20))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsAccentDeep)
                }
                .padding(.top, DS.Spacing.sm)
                Text("Estimated savings — your call, not ours.")
                    .font(.dsBody(12.5))
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
    }

    private var combinedSavings: String? {
        guard let currency = primaryCurrency else { return nil }
        let total = suggestions.compactMap(\.annualSaving).reduce(Decimal.zero, +)
        guard total > 0, suggestions.count > 1 else { return nil }
        return Money(amount: total, currencyCode: currency).formatted() + "/yr"
    }
}
