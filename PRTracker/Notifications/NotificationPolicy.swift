import Foundation

enum NotificationPolicy {
    static func shouldNotify(level: NotificationLevel, candidate: NotificationCandidate.Kind, pr: PRContext, viewerLogin: String) -> Bool {
        if level == .none { return false }
        if let actor = actorLogin(for: candidate), actor == viewerLogin { return false }
        if level == .everything { return everythingAllows(candidate) }
        return personalAllows(candidate, pr: pr, viewerLogin: viewerLogin)
    }

    private static func everythingAllows(_ k: NotificationCandidate.Kind) -> Bool {
        switch k {
        case .issueComment, .codeComment, .reviewSubmitted,
             .stateChange, .headPushed, .opened, .ciFailure:
            return true
        }
    }

    private static func personalAllows(_ k: NotificationCandidate.Kind, pr: PRContext, viewerLogin: String) -> Bool {
        if pr.authorLogin == viewerLogin { return everythingAllows(k) }
        switch k {
        case .codeComment(_, _, let inReplyToAuthor, _, _, _):
            return inReplyToAuthor == viewerLogin
        case .issueComment:
            return pr.viewerHasCommented
        default:
            return false
        }
    }

    private static func actorLogin(for k: NotificationCandidate.Kind) -> String? {
        switch k {
        case .issueComment(_, let a, _): return a
        case .codeComment(_, let a, _, _, _, _): return a
        case .reviewSubmitted(_, let a, _): return a
        case .stateChange(_, let a): return a
        case .headPushed(_, let a): return a
        case .opened(let a): return a
        case .ciFailure: return nil
        }
    }
}
