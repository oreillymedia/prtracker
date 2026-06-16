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
