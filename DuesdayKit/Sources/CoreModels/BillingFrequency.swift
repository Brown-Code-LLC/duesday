import Foundation

/// How often a subscription bills. `custom` requires an accompanying ``CustomInterval``.
/// Display strings move to a String Catalog in the localization phase (roadmap P7).
public enum BillingFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case semiannual
    case annual
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiannual: "Every 6 months"
        case .annual: "Yearly"
        case .custom: "Custom"
        }
    }
}

/// A user-defined billing interval, e.g. every 2 weeks or every 3 months.
public struct CustomInterval: Hashable, Codable, Sendable {
    public enum Unit: String, CaseIterable, Codable, Sendable, Identifiable {
        case day, week, month, year
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .day: "day(s)"
            case .week: "week(s)"
            case .month: "month(s)"
            case .year: "year(s)"
            }
        }
    }

    public var count: Int
    public var unit: Unit

    public init(count: Int, unit: Unit) {
        self.count = max(1, count)
        self.unit = unit
    }
}
