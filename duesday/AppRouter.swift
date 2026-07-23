import Foundation
import Observation

/// App-level tab identity. Cross-feature navigation is routed here so feature
/// modules never depend on each other (ADR-1).
enum AppTab: Hashable {
    case overview
    case subscriptions
    case calendar
    case insights
}

/// Shared navigation state: tab selection plus pending deep-link targets
/// (notification taps land here and are consumed by the subscriptions tab).
@Observable
final class AppRouter {
    var selectedTab: AppTab = .overview
    var pendingSubscriptionID: UUID?

    func openSubscription(id: UUID) {
        selectedTab = .subscriptions
        pendingSubscriptionID = id
    }
}
