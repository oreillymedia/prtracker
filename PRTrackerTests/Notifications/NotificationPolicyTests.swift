import Testing
import Foundation
@testable import PRTracker

@Suite struct NotificationPolicyTests {
    private let me = "alex"
    private let other = "iris"

    private func ctx(author: String = "iris", viewerCommented: Bool = false) -> PRContext {
        PRContext(id: "PR_1", authorLogin: author, viewerHasCommented: viewerCommented)
    }

    // MARK: level == .none

    @Test func noneNeverFires() {
        let c = ctx()
        #expect(NotificationPolicy.shouldNotify(level: .none, candidate: .issueComment(eventID: "e1", authorLogin: other, body: "hi"), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .none, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me) == false)
    }

    // MARK: level == .everything (non-self actor)

    @Test func everythingFiresForIssueComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .issueComment(eventID: "e1", authorLogin: other, body: "hi"), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForCodeComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .codeComment(commentID: "c1", authorLogin: other, inReplyToAuthorLogin: nil, body: "lgtm", path: "a.swift", line: 10), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForReviewSubmitted() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .reviewSubmitted(eventID: "r1", authorLogin: other, state: .approved), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForCIFailure() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .ciFailure(runID: 7), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForStateChange() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .stateChange(newState: .merged, actorLogin: other), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForHeadPushed() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForOpened() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .opened(authorLogin: other), pr: ctx(), viewerLogin: me))
    }

    // MARK: level == .everything (self actor → filtered)

    @Test func everythingSkipsSelfComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .issueComment(eventID: "e1", authorLogin: me, body: "yo"), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func everythingSkipsSelfReview() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .reviewSubmitted(eventID: "r1", authorLogin: me, state: .approved), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func everythingSkipsSelfPush() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .headPushed(headSha: "abc", actorLogin: me), pr: ctx(), viewerLogin: me) == false)
    }

    // MARK: level == .personal, viewer authored PR

    @Test func personalMyPRFiresOnEveryKind() {
        let c = ctx(author: me)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(eventID: "e1", authorLogin: other, body: "hi"), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(commentID: "c1", authorLogin: other, inReplyToAuthorLogin: nil, body: "x", path: "p", line: 1), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .reviewSubmitted(eventID: "r1", authorLogin: other, state: .approved), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .stateChange(newState: .merged, actorLogin: other), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .opened(authorLogin: me), pr: c, viewerLogin: me) == false) // self
    }

    // MARK: level == .personal, viewer did NOT author

    @Test func personalCodeReplyToMeFires() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(commentID: "c1", authorLogin: other, inReplyToAuthorLogin: me, body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me))
    }
    @Test func personalCodeReplyToSomeoneElseDoesNotFire() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(commentID: "c1", authorLogin: other, inReplyToAuthorLogin: "rina", body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func personalCodeTopLevelDoesNotFire() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(commentID: "c1", authorLogin: other, inReplyToAuthorLogin: nil, body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func personalIssueCommentFiresIfViewerHasCommented() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(eventID: "e1", authorLogin: other, body: "x"), pr: ctx(viewerCommented: true), viewerLogin: me))
    }
    @Test func personalIssueCommentDoesNotFireIfViewerHasNotCommented() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(eventID: "e1", authorLogin: other, body: "x"), pr: ctx(viewerCommented: false), viewerLogin: me) == false)
    }
    @Test func personalDoesNotFireOnOtherKindsForNonAuthor() {
        let c = ctx(viewerCommented: true)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .reviewSubmitted(eventID: "r1", authorLogin: other, state: .approved), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .stateChange(newState: .merged, actorLogin: other), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .opened(authorLogin: other), pr: c, viewerLogin: me) == false)
    }
}
