import Foundation
import Notifications
import UserNotifications

/// UNUserNotificationCenter delegate: shows banners in the foreground and
/// turns notification taps into subscription deep links.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var onOpenSubscription: ((UUID) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard
            let idString = userInfo[DuesdayNotification.subscriptionIDKey] as? String,
            let id = UUID(uuidString: idString)
        else { return }
        await MainActor.run {
            onOpenSubscription?(id)
        }
    }
}
