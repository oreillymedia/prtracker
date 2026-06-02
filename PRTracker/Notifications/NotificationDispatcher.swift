import Foundation
import SwiftData
import UserNotifications

final class NotificationDispatcher {
    private let modelContainer: ModelContainer
    private let poster: NotificationPoster
    private let auth: NotificationAuthorizing
    private let activity: AppActivityProbing

    init(modelContainer: ModelContainer, poster: NotificationPoster, auth: NotificationAuthorizing = NotificationAuthorization(), activity: AppActivityProbing = NSAppActivityProbe()) {
        self.modelContainer = modelContainer
        self.poster = poster
        self.auth = auth
        self.activity = activity
    }

    func process(repoID: String) async {
        let ctx = ModelContext(modelContainer)
        guard let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first else { return }
        if vs.notificationLevel == .none { return }

        if await auth.currentStatus() != .authorized { return }
        if await MainActor.run(body: { activity.isFrontmost() }) { return }
        guard let viewerLogin = vs.viewer?.login else { return }

        _ = viewerLogin // suppress unused warning until Task 8 wires the real work
    }
}
