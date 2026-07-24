import Foundation
import os

/// De-identified product telemetry. The API deliberately accepts only a
/// closed event enum and integer counts, so merchants, amounts, addresses,
/// message content, and tokens cannot be attached accidentally.
public actor PrivacyAnalytics {
    public enum Event: String, Sendable {
        case onboardingCompleted
        case manualEntryCreated
        case importProcessed
        case candidateConfirmed
        case candidateRejected
        case syncCompleted
        case exportCreated
    }

    public protocol Sink: Sendable {
        func record(event: String, count: Int) async
    }

    private let sink: (any Sink)?
    private let logger = Logger(subsystem: "app.duesday", category: "analytics")

    public init(sink: (any Sink)? = nil) {
        self.sink = sink
    }

    public func record(_ event: Event, count: Int = 1) async {
        let safeCount = max(0, count)
        logger.debug("event=\(event.rawValue, privacy: .public) count=\(safeCount, privacy: .public)")
        await sink?.record(event: event.rawValue, count: safeCount)
    }
}
