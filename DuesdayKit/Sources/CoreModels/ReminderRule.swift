import Foundation
import SwiftData

/// A user-configured reminder for a subscription (billing day, N days before,
/// trial end, …). The notification engine turns enabled rules into the
/// nearest-N scheduled local notifications.
@Model
public final class ReminderRule {
    @Attribute(.unique) public var id: UUID
    public var subscription: Subscription?
    public var reminderTypeRaw: String
    /// Days before the event to fire; 0 means the day itself.
    public var leadTimeDays: Int
    /// Minutes from local midnight (e.g. 9:00 → 540). Scheduled with calendar
    /// components so DST and time-zone changes resolve correctly.
    public var timeOfDayMinutes: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        reminderType: ReminderType,
        leadTimeDays: Int = 0,
        timeOfDayMinutes: Int = 9 * 60,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.reminderTypeRaw = reminderType.rawValue
        self.leadTimeDays = max(0, leadTimeDays)
        self.timeOfDayMinutes = min(max(0, timeOfDayMinutes), 24 * 60 - 1)
        self.isEnabled = isEnabled
    }
}

extension ReminderRule {
    public var reminderType: ReminderType {
        get { ReminderType(rawValue: reminderTypeRaw) ?? .beforeBilling }
        set { reminderTypeRaw = newValue.rawValue }
    }

    /// Standard lead-time presets offered in reminder configuration
    /// (spec: notification engine).
    public static let standardLeadTimesDays: [Int] = [0, 1, 3, 7, 14, 30]
}
