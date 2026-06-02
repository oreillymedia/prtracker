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

    /// Semantically: the most recent moment the user selected this PR's row.
    /// Backed by the same column as `lastReadAt` to avoid a SwiftData
    /// migration. New code reads `lastSeenAt`; legacy code reads `lastReadAt`.
    var lastSeenAt: Date? { lastReadAt }

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
    @Relationship(deleteRule: .cascade, inverse: \ReviewComment.pullRequest)
    var reviewComments: [ReviewComment] = []
    @Relationship(deleteRule: .cascade, inverse: \NotificationLog.pullRequest)
    var notificationLogs: [NotificationLog] = []

    var state: PRState {
        get { PRState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }
    /// Aggregate review state, derived from `reviewers`. Mirrors GitHub's
    /// precedence: any changes-requested wins, else any approved, else any
    /// commented, else pending if anyone is on the hook, else nil.
    /// `reviewStateRaw` is retained on the schema for back-compat (no migration),
    /// but only consulted if there are no reviewers at all.
    var reviewState: ReviewState? {
        if reviewers.contains(where: { $0.state == .changesRequested }) { return .changesRequested }
        if reviewers.contains(where: { $0.state == .approved })         { return .approved }
        if reviewers.contains(where: { $0.state == .commented })        { return .commented }
        if !reviewers.isEmpty                                            { return .pending }
        return reviewStateRaw.flatMap(ReviewState.init(rawValue:))
    }
    var mergeable: Mergeable {
        get { Mergeable(rawValue: mergeableRaw) ?? .unknown }
        set { mergeableRaw = newValue.rawValue }
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
