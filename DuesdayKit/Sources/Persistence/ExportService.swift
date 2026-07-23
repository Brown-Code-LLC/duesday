import CoreModels
import Foundation
import SwiftData

/// User-facing data export (spec: required feature 16). Exports the user's
/// subscription records — no raw email content exists to export because none
/// is retained (privacy model).
public struct SubscriptionExportRecord: Codable {
    public let id: UUID
    public let merchantName: String
    public let planName: String?
    public let amount: Decimal
    public let currencyCode: String
    public let billingFrequency: String
    public let customIntervalCount: Int?
    public let customIntervalUnit: String?
    public let status: String
    public let category: String
    public let ownershipType: String
    public let startDate: Date?
    public let trialEndDate: Date?
    public let nextBillingDate: Date?
    public let lastBillingDate: Date?
    public let paymentMethodLabel: String?
    public let websiteURL: String?
    public let cancellationURL: String?
    public let cancellationInstructions: String?
    public let notes: String?
    public let detectionSource: String
    public let createdAt: Date
    public let archivedAt: Date?

    init(_ subscription: Subscription) {
        id = subscription.id
        merchantName = subscription.merchantName
        planName = subscription.planName
        amount = subscription.amount
        currencyCode = subscription.currencyCode
        billingFrequency = subscription.billingFrequencyRaw
        customIntervalCount = subscription.customInterval?.count
        customIntervalUnit = subscription.customInterval?.unit.rawValue
        status = subscription.statusRaw
        category = subscription.categoryRaw
        ownershipType = subscription.ownershipTypeRaw
        startDate = subscription.startDate
        trialEndDate = subscription.trialEndDate
        nextBillingDate = subscription.nextBillingDate
        lastBillingDate = subscription.lastBillingDate
        paymentMethodLabel = subscription.paymentMethodLabel
        websiteURL = subscription.websiteURL?.absoluteString
        cancellationURL = subscription.cancellationURL?.absoluteString
        cancellationInstructions = subscription.cancellationInstructions
        notes = subscription.notes
        detectionSource = subscription.detectionSourceRaw
        createdAt = subscription.createdAt
        archivedAt = subscription.archivedAt
    }
}

public struct ExportPayload: Codable {
    public let exportedAt: Date
    public let appVersion: String
    public let subscriptions: [SubscriptionExportRecord]
}

public final class DataExporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    private func records() throws -> [SubscriptionExportRecord] {
        var descriptor = FetchDescriptor<Subscription>()
        descriptor.sortBy = [SortDescriptor(\.merchantName, comparator: .localizedStandard)]
        return try context.fetch(descriptor).map(SubscriptionExportRecord.init)
    }

    public func jsonData(appVersion: String = "1.0") throws -> Data {
        let payload = ExportPayload(
            exportedAt: .now,
            appVersion: appVersion,
            subscriptions: try records()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public func csvData() throws -> Data {
        let header = [
            "merchant", "plan", "amount", "currency", "frequency", "status",
            "category", "ownership", "next_billing_date", "trial_end_date",
            "start_date", "payment_method", "website", "cancellation_url", "notes",
        ]
        let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

        func field(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return "" }
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        func dateField(_ date: Date?) -> String {
            date.map { $0.formatted(dateFormat) } ?? ""
        }

        var lines = [header.joined(separator: ",")]
        for record in try records() {
            lines.append([
                field(record.merchantName),
                field(record.planName),
                "\(record.amount)",
                record.currencyCode,
                record.billingFrequency,
                record.status,
                record.category,
                record.ownershipType,
                dateField(record.nextBillingDate),
                dateField(record.trialEndDate),
                dateField(record.startDate),
                field(record.paymentMethodLabel),
                field(record.websiteURL),
                field(record.cancellationURL),
                field(record.notes),
            ].joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}

/// Full local-data deletion (spec: required feature 17). Removes every entity;
/// notification cleanup is the caller's responsibility (ReminderScheduler).
public final class DataEraser {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func eraseAll() throws {
        try context.delete(model: RenewalEvent.self)
        try context.delete(model: ReminderRule.self)
        try context.delete(model: Subscription.self)
        try context.delete(model: DetectionCandidate.self)
        try context.delete(model: ImportedDocument.self)
        try context.delete(model: UserAccount.self)
        try context.save()
    }
}
