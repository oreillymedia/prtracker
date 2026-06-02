import Foundation
import AppKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if await MainActor.run(body: { NSApp.isActive }) { return [] }
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let prID = response.notification.request.content.userInfo["prID"] as? String else { return }
        await MainActor.run {
            appState?.selectedPRID = prID
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
