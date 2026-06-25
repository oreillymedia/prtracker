import Foundation
import SwiftData

@Model
final class Repo {
    @Attribute(.unique) var id: String   // "owner/name"
    var owner: String
    var name: String
    var lastFetchedAt: Date?
    var isEnabled: Bool
    var notificationLevelRaw: String = NotificationLevel.personal.rawValue
    /// True once the background loop has fetched this repo's PR threads
    /// (timeline/reviews/comments) and recorded a silent notification baseline.
    /// Until then, the first thread sync baselines instead of notifying — this
    /// prevents a backlog flood the first time threads are fetched (new repo, or
    /// the first run after thread polling was added).
    var didBaselineThreads: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PullRequest.repo)
    var pullRequests: [PullRequest] = []

    /// Per-repo notification level. `isEnabled` (visible + synced) and this are
    /// orthogonal: an enabled repo may be `.none` (shown in the UI, but silent).
    var notificationLevel: NotificationLevel {
        get { NotificationLevel(rawValue: notificationLevelRaw) ?? .personal }
        set { notificationLevelRaw = newValue.rawValue }
    }

    init(owner: String, name: String, isEnabled: Bool = true) {
        self.id = "\(owner)/\(name)"
        self.owner = owner
        self.name = name
        self.isEnabled = isEnabled
    }
}
