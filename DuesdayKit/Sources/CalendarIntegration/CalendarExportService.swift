import CoreModels
import Foundation

#if canImport(EventKit)
import EventKit

public enum CalendarExportError: Error {
    case accessDenied
    case calendarUnavailable
}

@MainActor
public final class CalendarExportService {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    @discardableResult
    public func export(_ subscription: Subscription) async throws -> String {
        guard let date = subscription.nextBillingDate else {
            throw CalendarExportError.calendarUnavailable
        }
        let granted = try await eventStore.requestWriteOnlyAccessToEvents()
        guard granted else { throw CalendarExportError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarExportError.calendarUnavailable
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = "\(subscription.merchantName) renewal"
        event.startDate = Calendar.current.startOfDay(for: date)
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: event.startDate)
        event.isAllDay = true
        event.notes = "\(subscription.money.formatted()) · \(subscription.billingFrequency.displayName)"
        event.url = subscription.websiteURL
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
}
#else
public enum CalendarExportError: Error { case calendarUnavailable }
@MainActor
public final class CalendarExportService {
    public init() {}
    public func export(_ subscription: Subscription) async throws -> String {
        throw CalendarExportError.calendarUnavailable
    }
}
#endif
