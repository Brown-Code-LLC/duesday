import Foundation

/// User-configurable notification behavior. Non-sensitive by design — safe in
/// UserDefaults (contains no merchant names, amounts, or credentials).
public struct NotificationPreferences: Hashable, Sendable, Codable {
    /// Amounts appear in notification bodies only when the user opts in
    /// (privacy model: no sensitive details on the lock screen by default).
    public var includeAmounts: Bool
    public var quietHoursEnabled: Bool
    /// Quiet window in minutes from local midnight; may span midnight
    /// (e.g. 22:00 → 07:00).
    public var quietStartMinutes: Int
    public var quietEndMinutes: Int
    /// Defaults applied to new subscriptions' reminder rules.
    public var defaultLeadDays: Int
    public var defaultTimeOfDayMinutes: Int
    /// Trials get their own defaults — typically two reminders (spec 1r:
    /// "Trials get two reminders — you asked to never miss one").
    public var trialLeadDays: [Int]
    /// Merge same-day reminders into one daily summary notification.
    public var digestEnabled: Bool
    /// Gate detection-driven alerts (wired to the email pipeline in Phase 3;
    /// stored now so the preference survives).
    public var priceChangeAlerts: Bool
    public var failedPaymentAlerts: Bool

    public init(
        includeAmounts: Bool = false,
        quietHoursEnabled: Bool = false,
        quietStartMinutes: Int = 22 * 60,
        quietEndMinutes: Int = 7 * 60,
        defaultLeadDays: Int = 3,
        defaultTimeOfDayMinutes: Int = 9 * 60,
        trialLeadDays: [Int] = [7, 1],
        digestEnabled: Bool = false,
        priceChangeAlerts: Bool = true,
        failedPaymentAlerts: Bool = true
    ) {
        self.includeAmounts = includeAmounts
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartMinutes = quietStartMinutes
        self.quietEndMinutes = quietEndMinutes
        self.defaultLeadDays = defaultLeadDays
        self.defaultTimeOfDayMinutes = defaultTimeOfDayMinutes
        self.trialLeadDays = trialLeadDays
        self.digestEnabled = digestEnabled
        self.priceChangeAlerts = priceChangeAlerts
        self.failedPaymentAlerts = failedPaymentAlerts
    }

    public var quietHours: QuietHours? {
        quietHoursEnabled
            ? QuietHours(startMinutes: quietStartMinutes, endMinutes: quietEndMinutes)
            : nil
    }

    // MARK: - Persistence (UserDefaults)

    private static let storageKey = "duesday.notification.preferences"

    public static func load(from defaults: UserDefaults = .standard) -> NotificationPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else { return NotificationPreferences() }
        return preferences
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// A daily do-not-disturb window. Reminders that would fire inside it are
/// deferred to the window's end.
public struct QuietHours: Hashable, Sendable, Codable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = min(max(0, startMinutes), 24 * 60 - 1)
        self.endMinutes = min(max(0, endMinutes), 24 * 60 - 1)
    }

    public func contains(minuteOfDay minute: Int) -> Bool {
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes {
            return minute >= startMinutes && minute < endMinutes
        }
        // Overnight window, e.g. 22:00 → 07:00.
        return minute >= startMinutes || minute < endMinutes
    }
}
