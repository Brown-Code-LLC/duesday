import CoreModels
import Foundation
import SwiftData
import os

/// Owns the app's `ModelContainer`. Built through `bootstrap(inMemory:)`, which
/// degrades to an in-memory store instead of crashing when the persistent
/// store cannot be opened — the failure is surfaced to the UI, not swallowed.
public final class PersistenceController {
    public let container: ModelContainer
    /// True when this controller is backed by an in-memory store (previews,
    /// tests, sample-data mode, or persistent-store failure fallback).
    public let isEphemeral: Bool

    private static let logger = DuesdayLog.logger(category: "persistence")

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: DuesdaySchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(
            for: schema,
            migrationPlan: DuesdayMigrationPlan.self,
            configurations: [configuration]
        )
        self.isEphemeral = inMemory
    }

    /// Result of app-launch store setup. `storeError` is non-nil when the
    /// persistent store failed and the app is running on a fallback in-memory
    /// store; the shell shows a storage warning in that case.
    public struct Bootstrap {
        public let controller: PersistenceController
        public let storeError: Error?
    }

    /// Opens the persistent store, falling back to in-memory on failure.
    /// A second failure (in-memory container creation) is not recoverable and
    /// is allowed to propagate.
    public static func bootstrap(inMemory: Bool = false) throws -> Bootstrap {
        if inMemory {
            return Bootstrap(controller: try PersistenceController(inMemory: true), storeError: nil)
        }
        do {
            return Bootstrap(controller: try PersistenceController(inMemory: false), storeError: nil)
        } catch {
            logger.error("Persistent store unavailable, falling back to in-memory: \(error, privacy: .public)")
            return Bootstrap(controller: try PersistenceController(inMemory: true), storeError: error)
        }
    }

    public var mainContext: ModelContext { container.mainContext }
}

/// Single-version plan today; every future schema change adds a stage here and
/// a migration test (ADR-2, roadmap P7).
public enum DuesdayMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [DuesdaySchemaV1.self]
    }

    public static var stages: [MigrationStage] { [] }
}
