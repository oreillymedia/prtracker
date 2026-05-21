import Foundation
import SwiftData

@Model
final class ReviewComment {
    @Attribute(.unique) var id: String   // "RC_<github-id>" surrogate
    var parentReviewIntegerID: Int?
    var inReplyToID: String?
    var author: User
    var body: String
    var path: String
    var line: Int?
    var diffHunk: String
    var createdAt: Date
    /// Local-only — never overwritten by sync.
    var isSeen: Bool
    var pullRequest: PullRequest

    init(id: String, parentReviewIntegerID: Int?, inReplyToID: String?, author: User,
         body: String, path: String, line: Int?, diffHunk: String, createdAt: Date,
         isSeen: Bool = false, pullRequest: PullRequest) {
        self.id = id
        self.parentReviewIntegerID = parentReviewIntegerID
        self.inReplyToID = inReplyToID
        self.author = author
        self.body = body
        self.path = path
        self.line = line
        self.diffHunk = diffHunk
        self.createdAt = createdAt
        self.isSeen = isSeen
        self.pullRequest = pullRequest
    }
}
