import Foundation
import SwiftData

@Model
final class PullRequest {
    @Attribute(.unique) var id: String   // GitHub node ID
    var number: Int
    var title: String
    var stateRaw: String
    var branchHead: String
    var branchBase: String
    var headSha: String
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var openedAt: Date
    var updatedAt: Date
    var mergedAt: Date?
    var reviewStateRaw: String?
    var mergeableRaw: String
    var ciPass: Int
    var ciFail: Int
    var ciRunning: Int
    var ciPending: Int
    var ciTotal: Int
    var attentionHint: String?
    var mentionHint: String?
    var involvedHint: String?
    var lastReadAt: Date?

    var author: User
    var repo: Repo

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.pullRequest)
    var timeline: [TimelineEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \Reviewer.pr)
    var reviewers: [Reviewer] = []
    @Relationship(deleteRule: .cascade, inverse: \Label.pr)
    var labels: [Label] = []
    @Relationship(deleteRule: .cascade, inverse: \CIRun.pr)
    var ciChecks: [CIRun] = []

    var state: PRState {
        get { PRState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }
    var reviewState: ReviewState? {
        get { reviewStateRaw.flatMap(ReviewState.init(rawValue:)) }
        set { reviewStateRaw = newValue?.rawValue }
    }
    var mergeable: Mergeable {
        get { Mergeable(rawValue: mergeableRaw) ?? .unknown }
        set { mergeableRaw = newValue.rawValue }
    }

    /// A PR is unread iff it's never been read, or its `updatedAt` is newer than the last read time.
    var isUnread: Bool {
        guard let lastReadAt else { return true }
        return updatedAt > lastReadAt
    }

    init(id: String, number: Int, title: String, state: PRState, branchHead: String, branchBase: String, headSha: String, openedAt: Date, updatedAt: Date, author: User, repo: Repo) {
        self.id = id
        self.number = number
        self.title = title
        self.stateRaw = state.rawValue
        self.branchHead = branchHead
        self.branchBase = branchBase
        self.headSha = headSha
        self.additions = 0; self.deletions = 0; self.changedFiles = 0
        self.openedAt = openedAt; self.updatedAt = updatedAt
        self.mergeableRaw = Mergeable.unknown.rawValue
        self.ciPass = 0; self.ciFail = 0; self.ciRunning = 0; self.ciPending = 0; self.ciTotal = 0
        self.author = author
        self.repo = repo
    }
}
