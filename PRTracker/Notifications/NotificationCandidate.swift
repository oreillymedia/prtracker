import Foundation

struct NotificationCandidate {
    enum Kind {
        case issueComment(eventID: String, authorLogin: String, body: String)
        case codeComment(commentID: String, authorLogin: String, inReplyToAuthorLogin: String?, body: String, path: String, line: Int?)
        case reviewSubmitted(eventID: String, authorLogin: String, state: ReviewState)
        case ciFailure(runID: Int)
        case stateChange(newState: PRState, actorLogin: String?)
        case headPushed(headSha: String, actorLogin: String?)
        case opened(authorLogin: String)
    }

    let kind: Kind
    let prID: String
}

struct PRContext {
    let id: String
    let authorLogin: String
    /// True when the viewer has authored at least one TimelineEvent.comment or ReviewComment on this PR.
    let viewerHasCommented: Bool
}
