import Foundation
import SwiftData

@Model
final class TimelineEvent {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var at: Date
    var actor: User?
    var body: String?
    var sha: String?
    var reviewID: Int?
    /// GitHub's numeric database ID for the underlying issue-comment / commit /
    /// review event. Used to build per-thread anchor URLs (e.g.
    /// `#issuecomment-<id>`). May be nil for rows synced before this column
    /// existed; resync repopulates.
    var numericID: Int?
    var reviewStateRaw: String?
    /// Local-only — never overwritten by sync.
    var isSeen: Bool
    /// Local-only — never overwritten by sync. True when the user has marked
    /// this comment-style event as addressed. Only meaningful for `type == .comment`.
    var isDone: Bool = false

    var pullRequest: PullRequest

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .comment }
        set { typeRaw = newValue.rawValue }
    }
    var reviewState: ReviewState? {
        get { reviewStateRaw.flatMap(ReviewState.init(rawValue:)) }
        set { reviewStateRaw = newValue?.rawValue }
    }

    init(id: String, type: EventType, at: Date, pullRequest: PullRequest, actor: User? = nil, body: String? = nil, sha: String? = nil, reviewState: ReviewState? = nil, isSeen: Bool = false) {
        self.id = id
        self.typeRaw = type.rawValue
        self.at = at
        self.pullRequest = pullRequest
        self.actor = actor
        self.body = body
        self.sha = sha
        self.reviewStateRaw = reviewState?.rawValue
        self.isSeen = isSeen
    }
}
