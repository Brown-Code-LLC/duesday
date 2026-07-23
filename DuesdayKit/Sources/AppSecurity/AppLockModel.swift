import Foundation
import LocalAuthentication
import Observation

/// Face ID / device-passcode app lock. The enabled flag lives in UserDefaults
/// (a boolean preference, not a secret — the enforcement is biometric).
/// Enabling requires a successful authentication first so users can't lock
/// themselves out with a policy they can't satisfy.
@Observable
public final class AppLockModel {
    private static let storageKey = "duesday.applock.enabled"

    public private(set) var isEnabled: Bool
    public private(set) var isLocked: Bool
    public private(set) var lastError: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.storageKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    /// Human-readable name of the available biometry, for settings copy.
    public var biometryDescription: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "Device passcode"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Device passcode"
        }
    }

    public var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Called when the app leaves the foreground.
    public func lock() {
        if isEnabled { isLocked = true }
    }

    /// Attempts biometric/passcode unlock.
    @discardableResult
    public func unlock() async -> Bool {
        guard isLocked else { return true }
        if await authenticate(reason: "Unlock Duesday") {
            isLocked = false
            lastError = nil
            return true
        }
        return false
    }

    /// Toggles the lock preference; turning it on (or off) requires passing
    /// authentication so the change is owner-approved.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        guard isAvailable else {
            lastError = "No Face ID, Touch ID, or passcode is set up on this device."
            return false
        }
        let reason = enabled ? "Enable app lock" : "Disable app lock"
        guard await authenticate(reason: reason) else { return false }

        isEnabled = enabled
        defaults.set(enabled, forKey: Self.storageKey)
        if !enabled { isLocked = false }
        lastError = nil
        return true
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
