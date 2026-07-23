import CoreModels
import Foundation

/// Bridges SwiftData models into the planner's value-type inputs.
extension Subscription {
    public var reminderSubjectInput: ReminderSubjectInput {
        ReminderSubjectInput(
            id: id,
            merchantName: merchantName,
            amount: amount,
            currencyCode: currencyCode,
            status: status,
            isArchived: isArchived,
            nextBillingDate: nextBillingDate,
            trialEndDate: trialEndDate,
            frequency: billingFrequency,
            customInterval: customInterval,
            rules: reminderRules.map(\.spec)
        )
    }
}

extension ReminderRule {
    public var spec: ReminderRuleSpec {
        ReminderRuleSpec(
            id: id,
            type: reminderType,
            leadTimeDays: leadTimeDays,
            timeOfDayMinutes: timeOfDayMinutes,
            isEnabled: isEnabled
        )
    }
}
