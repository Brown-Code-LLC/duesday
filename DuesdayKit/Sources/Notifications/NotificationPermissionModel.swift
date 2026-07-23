import Foundation
import Observation
import UserNotifications

/// Observable permission state driving the pre-permission education flow:
/// the system prompt is only shown after the user has seen an explanation and
/// explicitly opted in (spec: notification engine).
@Observable
public final class NotificationPermissionModel {
    public enum Status: Sendable {
        case unknown
        case notDetermined
        case denied
        case authorized
    }

    public private(set) var status: Status = .unknown
    private let client: NotificationClient

    public init(client: NotificationClient = SystemNotificationClient()) {
        self.client = client
    }

    public func refresh() async {
        switch await client.authorizationStatus() {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        case .authorized, .provisional, .ephemeral: status = .authorized
        @unknown default: status = .unknown
        }
    }

    /// Presents the system prompt. Returns whether permission was granted.
    @discardableResult
    public func request() async -> Bool {
        let granted = (try? await client.requestAuthorization()) ?? false
        await refresh()
        return granted
    }
}
