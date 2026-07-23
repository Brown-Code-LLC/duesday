import Foundation
import SwiftData

/// One expected or observed billing occurrence for a subscription.
/// Currency is the parent subscription's; a currency change is a new detection.
@Model
public final class RenewalEvent {
    @Attribute(.unique) public var id: UUID
    public var subscription: Subscription?
    public var expectedDate: Date
    public var expectedAmount: Decimal?
    public var actualDate: Date?
    public var actualAmount: Decimal?
    public var statusRaw: String
    /// Provider message identifier that evidenced this renewal — never message content.
    public var sourceMessageID: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        expectedDate: Date,
        expectedAmount: Decimal? = nil,
        actualDate: Date? = nil,
        actualAmount: Decimal? = nil,
        status: RenewalStatus = .expected,
        sourceMessageID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.expectedDate = expectedDate
        self.expectedAmount = expectedAmount
        self.actualDate = actualDate
        self.actualAmount = actualAmount
        self.statusRaw = status.rawValue
        self.sourceMessageID = sourceMessageID
        self.createdAt = createdAt
    }
}

extension RenewalEvent {
    public var status: RenewalStatus {
        get { RenewalStatus(rawValue: statusRaw) ?? .expected }
        set { statusRaw = newValue.rawValue }
    }
}
