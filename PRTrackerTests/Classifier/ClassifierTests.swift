import Testing
import Foundation
@testable import PRTracker

@Suite struct ClassifierTests {
    private let me = "alex.chen"
    private let now = Date(timeIntervalSince1970: 1745_500_000) // 2026-04-24

    private func pr(id: String = "PR_1", number: Int = 1, author: String = "iris", state: String = "open", merged_at: Date? = nil, requested: [String] = [], reviewers: [(String, String)] = [], ciFail: Int = 0, ciRunning: Int = 0, commenters: [String] = [], updated: Date? = nil) -> ClassifierInput.PR {
        ClassifierInput.PR(id: id, number: number, authorLogin: author, state: state, mergedAt: merged_at, requestedReviewerLogins: requested, reviewerStates: reviewers, ciFail: ciFail, ciRunning: ciRunning, commenterLogins: commenters, updatedAt: updated ?? now.addingTimeInterval(-3600))
    }

    @Test func mineWithNoReviews() {
        let p = pr(author: me)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .mine)
    }

    @Test func mineWithFailingCIBecomesAttention() {
        let p = pr(author: me, ciFail: 2)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }

    @Test func mineWithChangesRequestedBecomesAttention() {
        let p = pr(author: me, reviewers: [("iris", "CHANGES_REQUESTED")])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }

    @Test func requestedReviewerNotYetReviewedIsReview() {
        let p = pr(author: "iris", requested: [me])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .review)
    }

    @Test func reviewerWhoApprovedIsInvolved() {
        let p = pr(author: "iris", reviewers: [(me, "APPROVED")])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .involved)
    }

    @Test func commenterIsInvolved() {
        let p = pr(author: "iris", commenters: [me])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .involved)
    }

    @Test func mentionPRIsMention() {
        let p = pr(id: "PR_M", author: "iris")
        let mentioned: Set<String> = ["PR_M"]
        #expect(Classifier.section(for: p, viewer: me, mentions: mentioned, now: now) == .mentions)
    }

    @Test func mergedWithin7DaysIsRecent() {
        let p = pr(author: "iris", state: "closed", merged_at: now.addingTimeInterval(-3 * 86400))
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .recent)
    }

    @Test func mergedOlderThan7DaysIsNil() {
        let p = pr(author: "iris", state: "closed", merged_at: now.addingTimeInterval(-8 * 86400))
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == nil)
    }

    @Test func attentionWinsOverMine() {
        let p = pr(author: me, ciFail: 1)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }
}

extension ClassifierTests {
    @Test func attentionHintForCIFailure() {
        let p = pr(author: me, ciFail: 2)
        #expect(Classifier.attentionHint(for: p)?.contains("CI") == true)
    }
}
