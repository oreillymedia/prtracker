import Foundation

enum Section: String, CaseIterable, Equatable {
    case attention, review, mentions, mine, involved, recent
    var lane: Lane {
        switch self {
        case .attention: .attention
        case .review:    .review
        case .mentions:  .mentions
        case .mine:      .mine
        case .involved:  .involved
        case .recent:    .recent
        }
    }
}

enum ClassifierInput {
    struct PR {
        let id: String
        let number: Int
        let authorLogin: String
        let state: String         // "open" | "closed"
        let mergedAt: Date?
        let requestedReviewerLogins: [String]
        let reviewerStates: [(String, String)]   // (login, state)
        let ciFail: Int
        let ciRunning: Int
        let commenterLogins: [String]
        let updatedAt: Date
    }
}

enum Classifier {
    /// Returns the single section the PR belongs to, or `nil` if it's not in the feed at all.
    static func section(for pr: ClassifierInput.PR, viewer: String, mentions: Set<String>, now: Date) -> Section? {
        // Recent merged: closed + merged within 7 days
        if pr.state == "closed", let m = pr.mergedAt, now.timeIntervalSince(m) <= 7 * 86400 {
            return .recent
        }
        if pr.state == "closed" { return nil }

        let isAuthor = pr.authorLogin == viewer
        let someoneRequestedChanges = pr.reviewerStates.contains { $0.1 == "CHANGES_REQUESTED" }
        let ciHasFailures = pr.ciFail > 0
        let amRequestedReviewer = pr.requestedReviewerLogins.contains(viewer)
        let myReviewState = pr.reviewerStates.first(where: { $0.0 == viewer })?.1
        let didReview = myReviewState != nil
        let didComment = pr.commenterLogins.contains(viewer)
        let mentioned = mentions.contains(pr.id)

        // attention precedence: my PR with problems
        if isAuthor && (ciHasFailures || someoneRequestedChanges) { return .attention }

        // mentions
        if mentioned { return .mentions }

        // needs my review: requested reviewer who hasn't reviewed
        if amRequestedReviewer && !didReview { return .review }

        // mine
        if isAuthor { return .mine }

        // involved: I've reviewed or commented
        if didReview || didComment { return .involved }

        return nil
    }
}

extension Classifier {
    static func attentionHint(for pr: ClassifierInput.PR) -> String? {
        if pr.ciFail > 0 { return "CI failed (\(pr.ciFail) check\(pr.ciFail == 1 ? "" : "s"))." }
        if pr.reviewerStates.contains(where: { $0.1 == "CHANGES_REQUESTED" }) {
            return "A reviewer requested changes."
        }
        return nil
    }
}
