import Foundation

// Enum clusters shared across entities. Fields filtered in #Predicate are stored
// as raw strings on the models (ADR-2); these enums are the typed surface.

public enum EmailProviderKind: String, CaseIterable, Codable, Sendable {
    case gmail
    case microsoft

    public var displayName: String {
        switch self {
        case .gmail: "Gmail"
        case .microsoft: "Microsoft Outlook"
        }
    }
}

public enum ConnectionStatus: String, CaseIterable, Codable, Sendable {
    case connected
    case expired
    case revoked
    case error
    case disconnected
}

public enum SubscriptionStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case active
    case trial
    case paused
    case canceled
    case expired

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .trial: "Trial"
        case .paused: "Paused"
        case .canceled: "Canceled"
        case .expired: "Expired"
        }
    }

    /// Statuses that still incur (or will incur) charges and count toward spending.
    public var countsTowardSpending: Bool {
        switch self {
        case .active, .trial: true
        case .paused, .canceled, .expired: false
        }
    }
}

public enum SubscriptionCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case streaming
    case music
    case software
    case productivity
    case news
    case fitness
    case gaming
    case utilities
    case insurance
    case food
    case shopping
    case education
    case finance
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .streaming: "Streaming"
        case .music: "Music"
        case .software: "Software"
        case .productivity: "Productivity"
        case .news: "News"
        case .fitness: "Fitness"
        case .gaming: "Gaming"
        case .utilities: "Utilities"
        case .insurance: "Insurance"
        case .food: "Food & Drink"
        case .shopping: "Shopping"
        case .education: "Education"
        case .finance: "Finance"
        case .other: "Other"
        }
    }

    /// SF Symbol used across list rows, badges, and the insights breakdown.
    public var symbolName: String {
        switch self {
        case .streaming: "play.tv"
        case .music: "music.note"
        case .software: "app.badge"
        case .productivity: "checklist"
        case .news: "newspaper"
        case .fitness: "figure.run"
        case .gaming: "gamecontroller"
        case .utilities: "bolt"
        case .insurance: "shield"
        case .food: "fork.knife"
        case .shopping: "bag"
        case .education: "graduationcap"
        case .finance: "banknote"
        case .other: "square.grid.2x2"
        }
    }
}

public enum OwnershipType: String, CaseIterable, Codable, Sendable, Identifiable {
    case personal
    case family
    case shared
    case business

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .personal: "Personal"
        case .family: "Family"
        case .shared: "Shared"
        case .business: "Business"
        }
    }
}

public enum DetectionSource: String, CaseIterable, Codable, Sendable {
    case manual
    case gmail
    case microsoft
    case importedDocument
    case shareExtension

    public var displayName: String {
        switch self {
        case .manual: "Added manually"
        case .gmail: "Detected from Gmail"
        case .microsoft: "Detected from Outlook"
        case .importedDocument: "Imported document"
        case .shareExtension: "Shared content"
        }
    }
}

public enum RenewalStatus: String, CaseIterable, Codable, Sendable {
    case expected
    case confirmed
    case missed
    case failed
    case refunded
}

public enum ReviewStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case confirmed
    case edited
    case merged
    case ignored
    case rejected
}

public enum ReminderType: String, CaseIterable, Codable, Sendable {
    case billingDay
    case beforeBilling
    case trialEnd
    case priceIncrease
    case paymentFailed
    case syncFailure
}

public enum ImportFileType: String, CaseIterable, Codable, Sendable {
    case pdf
    case image
    case emailFile
    case text
}

public enum ProcessingStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case processing
    case processed
    case failed
    case deleted
}
