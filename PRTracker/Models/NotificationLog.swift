import Foundation
import SwiftData

@Model
final class NotificationLog {
    @Attribute(.unique) var id: String
    var kind: String
    var notifiedAt: Date
    var pullRequest: PullRequest

    init(id: String, kind: String, notifiedAt: Date, pullRequest: PullRequest) {
        self.id = id
        self.kind = kind
        self.notifiedAt = notifiedAt
        self.pullRequest = pullRequest
    }
}
