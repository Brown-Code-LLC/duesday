import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Calendar per the design spec: month grid with a week-totals margin column,
/// dot markers (renewal / trial-ends / failed), a legend, and the selected
/// day's agenda under a strong rule. An Agenda mode groups the coming weeks
/// with running totals.
public struct RenewalCalendarView: View {
    private enum Mode: String, CaseIterable {
        case month = "Month"
        case agenda = "Agenda"
    }

    @Query(filter: #Predicate<Subscription> { $0.archivedAt == nil })
    private var subscriptions: [Subscription]

    @State private var mode: Mode = .month
    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                    modeToggle
                        .padding(.top, DS.Spacing.md)
                    if mode == .month {
                        monthGrid
                            .padding(.top, DS.Spacing.lg)
                        legend
                            .padding(.top, 4)
                        selectedDaySection
                    } else {
                        agendaList
                            .padding(.top, DS.Spacing.lg)
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

    // MARK: - Header

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(monthAnchor, format: .dateTime.month(.wide))
                .font(.dsTitle(30))
                .accessibilityAddTraits(.isHeader)
            if !calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .year) {
                Text(monthAnchor, format: .dateTime.year())
                    .font(.dsTitle(20))
                    .foregroundStyle(Color.dsInkSecondary)
            }
            if mode == .month {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsInkSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")
                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsInkSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }
            Spacer()
            if let due = monthDueTotal {
                Text("\(due.money.formatted()) due this month")
                    .font(.dsBody(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { candidate in
                let selected = mode == candidate
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { mode = candidate }
                    Haptics.selection()
                } label: {
                    Text(candidate.rawValue)
                        .font(.dsBody(12.5))
                        .foregroundStyle(selected ? Color.dsAccentDeep : Color.dsInkSecondary)
                        .frame(width: 100)
                        .frame(minHeight: 34)
                        .background(selected ? Color.dsAccentWash : Color.dsField)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.field)
                .stroke(Color.dsDivider, lineWidth: 1)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = shifted
            selectedDay = nil
        }
    }

    // MARK: - Month data

    private var countedSubscriptions: [Subscription] {
        subscriptions.filter { $0.status.countsTowardSpending }
    }

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: monthAnchor)
            ?? DateInterval(start: monthAnchor, duration: 0)
    }

    /// Charges inside the padded grid range (whole weeks covering the month).
    private var gridInterval: DateInterval {
        let start = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start
            ?? monthInterval.start
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end
        let end = calendar.dateInterval(of: .weekOfYear, for: lastDay)?.end ?? monthInterval.end
        return DateInterval(start: start, end: end)
    }

    private var gridCharges: [UpcomingCharges.Charge] {
        UpcomingCharges.charges(for: countedSubscriptions, within: gridInterval, calendar: calendar)
    }

    private var monthDueTotal: SpendingMath.CurrencyTotal? {
        UpcomingCharges.totals(for: countedSubscriptions, within: monthInterval, calendar: calendar).first
    }

    private func charges(on day: Date) -> [UpcomingCharges.Charge] {
        gridCharges.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func trialEnds(on day: Date) -> [Subscription] {
        countedSubscriptions.filter { sub in
            sub.trialEndDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }

    private func failedEvents(on day: Date) -> [(Subscription, RenewalEvent)] {
        subscriptions.flatMap { sub in
            sub.renewalEvents
                .filter { $0.status == .failed }
                .filter { calendar.isDate($0.actualDate ?? $0.expectedDate, inSameDayAs: day) }
                .map { (sub, $0) }
        }
    }

    // MARK: - Grid

    private var weekRows: [[Date]] {
        var rows: [[Date]] = []
        var cursor = gridInterval.start
        while cursor < gridInterval.end {
            var row: [Date] = []
            for offset in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: offset, to: cursor) {
                    row.append(day)
                }
            }
            rows.append(row)
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? gridInterval.end
        }
        return rows
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    private var monthGrid: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.dsCaption(9.5))
                        .tracking(DS.tracking(0.1, size: 9.5))
                        .foregroundStyle(Color.dsInkTertiary)
                        .frame(maxWidth: .infinity)
                }
                Text("WEEK")
                    .font(.dsCaption(9))
                    .tracking(DS.tracking(0.08, size: 9))
                    .foregroundStyle(Color.dsInkTertiary.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            ForEach(Array(weekRows.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(week, id: \.self) { day in
                        dayCell(day)
                    }
                    weekTotalCell(week)
                }
            }
        }
        .monospacedDigit()
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let dayCharges = charges(on: day)
        let hasTrialEnd = !trialEnds(on: day).isEmpty
        let hasFailure = !failedEvents(on: day).isEmpty

        return Button {
            selectedDay = day
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .font(.dsBody(13))
                    .foregroundStyle(dayNumberColor(inMonth: inMonth, isToday: isToday, isSelected: isSelected))
                    .frame(width: 24, height: 24)
                    .background {
                        if isToday {
                            Circle().fill(Color.dsInk)
                        } else if isSelected {
                            Circle().stroke(Color.dsAccent, lineWidth: 1)
                        }
                    }
                HStack(spacing: 2) {
                    if hasFailure {
                        Circle().fill(Color.dsDanger).frame(width: 4, height: 4)
                    }
                    if !dayCharges.isEmpty {
                        Circle().fill(Color.dsAccent).frame(width: 4, height: 4)
                    }
                    if hasTrialEnd {
                        Circle().stroke(Color.dsAccent, lineWidth: 1).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day, charges: dayCharges, trialEnd: hasTrialEnd, failed: hasFailure))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func dayNumberColor(inMonth: Bool, isToday: Bool, isSelected: Bool) -> Color {
        if isToday { return .dsPaper }
        if isSelected { return .dsAccentDeep }
        return inMonth ? .dsInk : .dsInkTertiary
    }

    private func dayAccessibilityLabel(_ day: Date, charges: [UpcomingCharges.Charge], trialEnd: Bool, failed: Bool) -> String {
        var label = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if !charges.isEmpty {
            label += ", \(charges.count) renewal\(charges.count == 1 ? "" : "s")"
        }
        if trialEnd { label += ", trial ends" }
        if failed { label += ", failed payment" }
        return label
    }

    private func weekTotalCell(_ week: [Date]) -> some View {
        let total = week
            .flatMap { charges(on: $0) }
            .map(\.money)
        let totals = SpendingMath.totalsByCurrency(total)
        return Text(totals.first.map { compactTotal($0) } ?? "")
            .font(.dsBody(10.5))
            .monospacedDigit()
            .foregroundStyle(Color.dsInkTertiary)
            .frame(width: 44, alignment: .trailing)
            .accessibilityLabel(totals.first.map { "Week total \($0.money.formatted())" } ?? "No charges this week")
    }

    private func compactTotal(_ total: SpendingMath.CurrencyTotal) -> String {
        Money(amount: total.total.rounded(scale: 0), currencyCode: total.currencyCode).formatted()
            .replacingOccurrences(of: #"[.,]00$"#, with: "", options: .regularExpression)
    }

    private var legend: some View {
        HStack(spacing: DS.Spacing.lg) {
            legendItem { Circle().fill(Color.dsAccent).frame(width: 5, height: 5) } text: { "renewal" }
            legendItem { Circle().stroke(Color.dsAccent, lineWidth: 1).frame(width: 6, height: 6) } text: { "trial ends" }
            legendItem { Circle().fill(Color.dsDanger).frame(width: 5, height: 5) } text: { "failed" }
        }
        .accessibilityHidden(true)
    }

    private func legendItem(@ViewBuilder marker: () -> some View, text: () -> String) -> some View {
        HStack(spacing: 5) {
            marker()
            Text(text())
                .font(.dsBody(10.5))
                .foregroundStyle(Color.dsInkTertiary)
        }
    }

    // MARK: - Selected day agenda

    @ViewBuilder
    private var selectedDaySection: some View {
        let day = selectedDay ?? defaultAgendaDay
        if let day {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color.dsRule).frame(height: 1)
                    .padding(.top, DS.Spacing.md)
                DSCaptionLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .padding(.top, DS.Spacing.md)
                    .accessibilityAddTraits(.isHeader)
                let dayCharges = charges(on: day)
                let trials = trialEnds(on: day)
                let failures = failedEvents(on: day)
                if dayCharges.isEmpty && trials.isEmpty && failures.isEmpty {
                    Text("Nothing due on this day.")
                        .font(.dsBody(13))
                        .foregroundStyle(Color.dsInkSecondary)
                        .padding(.vertical, DS.Spacing.md)
                }
                ForEach(Array(dayCharges.enumerated()), id: \.offset) { _, charge in
                    agendaRow(
                        subscription: charge.subscription,
                        title: "\(charge.subscription.merchantName) renews",
                        detail: charge.subscription.paymentMethodLabel,
                        amount: charge.money,
                        estimated: false
                    )
                }
                ForEach(trials) { subscription in
                    agendaRow(
                        subscription: subscription,
                        title: "\(subscription.merchantName) trial ends",
                        detail: (subscription.regularPrice ?? subscription.amount) > 0
                            ? "then \(Money(amount: subscription.regularPrice ?? subscription.amount, currencyCode: subscription.currencyCode).formatted())/mo"
                            : nil,
                        amount: nil,
                        estimated: false
                    )
                }
                ForEach(Array(failures.enumerated()), id: \.offset) { _, pair in
                    agendaRow(
                        subscription: pair.0,
                        title: "\(pair.0.merchantName) payment failed",
                        detail: "charge declined",
                        amount: pair.1.expectedAmount.map { Money(amount: $0, currencyCode: pair.0.currencyCode) },
                        estimated: false,
                        failure: true
                    )
                }
            }
        }
    }

    /// With nothing selected, show the next day in this month that has activity.
    private var defaultAgendaDay: Date? {
        let today = calendar.startOfDay(for: .now)
        return gridCharges
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 >= today && monthInterval.contains($0) }
            .min()
    }

    private func agendaRow(
        subscription: Subscription,
        title: String,
        detail: String?,
        amount: Money?,
        estimated: Bool,
        failure: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DSGlyphBox(
                    for: subscription.merchantName,
                    size: 36,
                    style: subscription.status == .trial ? .trial : .standard
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsBodyStrong(14.5))
                        .foregroundStyle(failure ? Color.dsDanger : Color.dsInk)
                    if let detail {
                        Text(detail)
                            .font(.dsBody(12))
                            .monospacedDigit()
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                }
                Spacer()
                if let amount {
                    AmountText(amount, estimated: estimated, presentation: .row)
                }
            }
            .padding(.vertical, 12)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Agenda mode (spec 1p: weeks with running totals)

    private struct WeekGroup {
        let start: Date
        let charges: [UpcomingCharges.Charge]
        let total: SpendingMath.CurrencyTotal?
    }

    private var agendaWeeks: [WeekGroup] {
        let window = UpcomingCharges.window(days: 60, calendar: calendar)
        let charges = UpcomingCharges.charges(for: countedSubscriptions, within: window, calendar: calendar)
        let grouped = Dictionary(grouping: charges) { charge in
            calendar.dateInterval(of: .weekOfYear, for: charge.date)?.start
                ?? calendar.startOfDay(for: charge.date)
        }
        return grouped.keys.sorted().map { start in
            let members = (grouped[start] ?? []).sorted { $0.date < $1.date }
            return WeekGroup(
                start: start,
                charges: members,
                total: SpendingMath.totalsByCurrency(members.map(\.money)).first
            )
        }
    }

    private var agendaList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agendaWeeks.isEmpty {
                Text("No upcoming renewals in the next 60 days.")
                    .font(.dsBody(13.5))
                    .foregroundStyle(Color.dsInkSecondary)
                    .padding(.vertical, DS.Spacing.lg)
            }
            ForEach(Array(agendaWeeks.enumerated()), id: \.offset) { _, week in
                DSSectionHeader(
                    weekTitle(week.start),
                    detail: week.total.map { $0.money.formatted() }
                )
                .padding(.top, DS.Spacing.lg)
                ForEach(Array(week.charges.enumerated()), id: \.offset) { _, charge in
                    agendaRow(
                        subscription: charge.subscription,
                        title: charge.subscription.merchantName,
                        detail: charge.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        amount: charge.money,
                        estimated: false
                    )
                }
            }
        }
    }

    private func weekTitle(_ start: Date) -> String {
        if calendar.isDate(start, equalTo: .now, toGranularity: .weekOfYear) {
            return "This week"
        }
        if let next = calendar.date(byAdding: .weekOfYear, value: 1, to: .now),
           calendar.isDate(start, equalTo: next, toGranularity: .weekOfYear) {
            return "Next week"
        }
        return "Week of \(start.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
