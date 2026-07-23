import CoreModels
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Subscriptions ledger per the design spec: serif title with count/total,
/// boxed search field, status filter chips, category groups with subtotal
/// headers, hairline rows.
public struct SubscriptionListView: View {
    private enum StatusFilter: String, CaseIterable {
        case active = "Active"
        case trials = "Trials"
        case paused = "Paused"
        case cancelled = "Cancelled"

        func matches(_ status: SubscriptionStatus) -> Bool {
            switch self {
            case .active: status == .active
            case .trials: status == .trial
            case .paused: status == .paused
            case .cancelled: status == .canceled || status == .expired
            }
        }
    }

    @Query(
        filter: #Predicate<Subscription> { $0.archivedAt == nil },
        sort: [SortDescriptor(\Subscription.merchantName, comparator: .localizedStandard)]
    )
    private var subscriptions: [Subscription]

    @State private var searchText = ""
    @State private var filter: StatusFilter = .active
    @State private var isPresentingAdd = false
    @FocusState private var searchFocused: Bool

    /// Deep-link target (notification taps): setting a subscription ID pushes
    /// its detail. Owned by the app-level router.
    @Binding private var externalTarget: UUID?

    public init(externalTarget: Binding<UUID?> = .constant(nil)) {
        self._externalTarget = externalTarget
    }

    private struct DetailTarget: Identifiable, Hashable {
        let id: UUID
    }

    private var externalTargetBinding: Binding<DetailTarget?> {
        Binding(
            get: { externalTarget.map(DetailTarget.init) },
            set: { externalTarget = $0?.id }
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                    searchField
                        .padding(.top, DS.Spacing.md)
                    filterChips
                        .padding(.top, DS.Spacing.sm)
                    if filtered.isEmpty {
                        emptyState
                            .padding(.top, DS.Spacing.xxl)
                    } else {
                        ForEach(groups, id: \.category) { group in
                            categoryGroup(group)
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
            .navigationDestination(item: externalTargetBinding) { target in
                if let subscription = subscriptions.first(where: { $0.id == target.id }) {
                    SubscriptionDetailView(subscription: subscription)
                } else {
                    MissingRecordView()
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                SubscriptionFormView()
            }
        }
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Subscriptions")
                .font(.dsTitle(30))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let summary = countSummary {
                Text(summary)
                    .font(.dsBody(12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsInkSecondary)
            }
            Button {
                isPresentingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.dsAccentDeep)
                    .frame(width: 30, height: 30)
                    .overlay { Circle().stroke(Color.dsAccent, lineWidth: 1) }
                    .frame(width: DS.minTouchTarget, height: DS.minTouchTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add subscription")
        }
        .padding(.top, DS.Spacing.sm)
    }

    private var countSummary: String? {
        let counted = subscriptions.filter { $0.status.countsTowardSpending }
        guard !counted.isEmpty else { return nil }
        let totals = SpendingMath.totalsByCurrency(
            counted.compactMap { sub in
                sub.estimatedMonthlyCost.map { Money(amount: $0, currencyCode: sub.currencyCode) }
            }
        )
        guard let primary = totals.first else { return "\(counted.count)" }
        return "\(counted.count) · \(primary.money.formatted())/mo"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsInkTertiary)
                .accessibilityHidden(true)
            TextField("Search merchants, plans, notes…", text: $searchText)
                .font(.dsBody(14))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.dsInkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.dsField, in: RoundedRectangle(cornerRadius: DS.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.field)
                .stroke(searchFocused ? Color.dsAccent : Color.dsDivider, lineWidth: 1)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StatusFilter.allCases, id: \.self) { candidate in
                    let count = subscriptions.count(where: { candidate.matches($0.status) })
                    DSFilterChip(
                        count > 0 ? "\(candidate.rawValue) · \(count)" : candidate.rawValue,
                        isSelected: filter == candidate
                    ) {
                        filter = candidate
                        Haptics.selection()
                    }
                }
            }
        }
    }

    // MARK: - Groups

    private struct CategoryGroup {
        let category: SubscriptionCategory
        let members: [Subscription]
        let subtotal: SpendingMath.CurrencyTotal?
    }

    private var filtered: [Subscription] {
        var result = subscriptions.filter { filter.matches($0.status) }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.merchantName.localizedCaseInsensitiveContains(query)
                    || ($0.planName?.localizedCaseInsensitiveContains(query) ?? false)
                    || ($0.notes?.localizedCaseInsensitiveContains(query) ?? false)
                    || $0.category.displayName.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    private var groups: [CategoryGroup] {
        Dictionary(grouping: filtered, by: \.category)
            .map { category, members in
                let totals = SpendingMath.totalsByCurrency(
                    members.compactMap { sub in
                        sub.estimatedMonthlyCost.map { Money(amount: $0, currencyCode: sub.currencyCode) }
                    }
                )
                return CategoryGroup(category: category, members: members, subtotal: totals.first)
            }
            .sorted { lhs, rhs in
                let l = lhs.subtotal?.total ?? -1
                let r = rhs.subtotal?.total ?? -1
                if l != r { return l > r }
                return lhs.category.displayName < rhs.category.displayName
            }
    }

    private func categoryGroup(_ group: CategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(
                group.category.displayName,
                detail: group.subtotal.map { "\($0.money.formatted())/mo" }
            )
            .padding(.top, DS.Spacing.lg)
            ForEach(group.members) { subscription in
                NavigationLink {
                    SubscriptionDetailView(subscription: subscription)
                } label: {
                    SubscriptionRowView(subscription: subscription)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Text(searchText.isEmpty ? "Nothing here yet" : "No matches")
                .font(.dsTitle(24))
            Text(searchText.isEmpty
                 ? "Entries with this status will appear here."
                 : "Nothing matches “\(searchText)”.")
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsInkSecondary)
            if searchText.isEmpty && filter == .active && subscriptions.isEmpty {
                Button("Add your first entry") { isPresentingAdd = true }
                    .buttonStyle(.dsPrimary)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

struct MissingRecordView: View {
    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("Entry not found")
                .font(.dsTitle(24))
            Text("It may have been deleted.")
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsInkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsPaper)
    }
}
