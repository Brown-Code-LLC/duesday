import Foundation
import os

/// Central logger factory. Interpolated values are private by default at call
/// sites — never log email bodies, tokens, merchant names, or amounts
/// (privacy model, hard rule 1).
public enum DuesdayLog {
    public static let subsystem = "app.duesday"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
