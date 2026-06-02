import Foundation
import UserNotifications

protocol NotificationPoster {
    func post(_ content: UNNotificationContent) async
}

struct UNCenterPoster: NotificationPoster {
    func post(_ content: UNNotificationContent) async {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
