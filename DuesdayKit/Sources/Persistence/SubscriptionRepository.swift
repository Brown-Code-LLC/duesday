import CoreModels
import Foundation
import SwiftData

/// Write path for subscriptions. Views read via `@Query` (ADR-5); all
/// mutations — from forms, the review queue, or the detection pipeline —
/// go through this seam so they stay testable and consistent.
public protocol SubscriptionRepository: AnyObject {
    func fetchAll(includeArchived: Bool) throws -> [Subscription]
    func fetch(id: UUID) throws -> Subscription?
    /// Case-insensitive duplicate lookup by normalized merchant name.
    func fetchByNormalizedMerchant(_ normalizedName: String) throws -> [Subscription]
    func insert(_ subscription: Subscription) throws
    func delete(_ subscription: Subscription) throws
    func archive(_ subscription: Subscription) throws
    func unarchive(_ subscription: Subscription) throws
    func save() throws
}

public final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchAll(includeArchived: Bool) throws -> [Subscription] {
        var descriptor: FetchDescriptor<Subscription>
        if includeArchived {
            descriptor = FetchDescriptor<Subscription>()
        } else {
            descriptor = FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.archivedAt == nil }
            )
        }
        descriptor.sortBy = [SortDescriptor(\.merchantName, comparator: .localizedStandard)]
        return try context.fetch(descriptor)
    }

    public func fetch(id: UUID) throws -> Subscription? {
        var descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchByNormalizedMerchant(_ normalizedName: String) throws -> [Subscription] {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.normalizedMerchantName == normalizedName }
        )
        return try context.fetch(descriptor)
    }

    public func insert(_ subscription: Subscription) throws {
        context.insert(subscription)
        try save()
    }

    public func delete(_ subscription: Subscription) throws {
        context.delete(subscription)
        try save()
    }

    public func archive(_ subscription: Subscription) throws {
        subscription.archivedAt = .now
        subscription.updatedAt = .now
        try save()
    }

    public func unarchive(_ subscription: Subscription) throws {
        subscription.archivedAt = nil
        subscription.updatedAt = .now
        try save()
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
