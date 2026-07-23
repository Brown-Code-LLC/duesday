import CoreModels
import Foundation
import Persistence
import SwiftData

/// In-memory containers for previews and tests.
public enum PreviewSupport {
    /// Empty in-memory controller. Traps only in previews/tests where an
    /// in-memory container failure means the schema itself is broken.
    public static func emptyController() -> PersistenceController {
        do {
            return try PersistenceController(inMemory: true)
        } catch {
            preconditionFailure("In-memory model container failed — schema is invalid: \(error)")
        }
    }

    /// In-memory controller pre-seeded with ``SampleData``.
    public static func seededController() -> PersistenceController {
        let controller = emptyController()
        do {
            try SampleData.seed(into: controller.mainContext)
        } catch {
            preconditionFailure("Sample data seeding failed: \(error)")
        }
        return controller
    }
}
