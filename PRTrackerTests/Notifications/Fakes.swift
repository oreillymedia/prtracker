import Foundation
import UserNotifications
@testable import PRTracker

final class CapturingPoster: NotificationPoster, @unchecked Sendable {
    var posted: [UNNotificationContent] = []
    func post(_ content: UNNotificationContent) async {
        posted.append(content)
    }
}

struct StubAuth: NotificationAuthorizing {
    let status: UNAuthorizationStatus
    func currentStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async -> UNAuthorizationStatus { status }
}

struct StubActivityProbe: AppActivityProbing {
    let frontmost: Bool
    @MainActor func isFrontmost() -> Bool { frontmost }
}
