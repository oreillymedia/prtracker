import Foundation
import UserNotifications

protocol NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> UNAuthorizationStatus
}

struct NotificationAuthorization: NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func requestAuthorization() async -> UNAuthorizationStatus {
        _ = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        return await currentStatus()
    }
}
