import CoreModels
import SwiftUI

/// Shared status styling so every feature renders states identically.
/// In the ledger aesthetic, status reads as an outlined pill: gold outline for
/// live money states (active/trial), neutral for the rest, rust for expired.
extension SubscriptionStatus {
    public var tint: Color {
        switch self {
        case .active, .trial: .dsAccentDeep
        case .paused, .canceled: .dsInkSecondary
        case .expired: .dsDanger
        }
    }

    public var pillStyle: DSTagPill.Style {
        switch self {
        case .active, .trial: .accent
        case .paused, .canceled, .expired: .neutral
        }
    }

    /// Capsule status pill used in detail headers.
    @ViewBuilder public var badge: some View {
        DSTagPill(displayName, style: pillStyle, capsule: true)
    }
}
