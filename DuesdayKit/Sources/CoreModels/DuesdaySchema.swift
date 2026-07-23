import Foundation
import SwiftData

/// Versioned schema, declared from day one so future changes go through an
/// explicit `SchemaMigrationPlan` with migration tests (ADR-2).
public enum DuesdaySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            UserAccount.self,
            Subscription.self,
            RenewalEvent.self,
            DetectionCandidate.self,
            ReminderRule.self,
            ImportedDocument.self,
        ]
    }
}
