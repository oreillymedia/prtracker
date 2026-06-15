import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct TodoHelpersTests {
    // MARK: - Fixture builder

    /// Returns a persistent container plus a live ModelContext (kept alive by the tuple),
    /// plus the PR and viewer user — all from the same context so callers can add to them.
    private func makePR(viewer: String = "alex", author: String = "dan") throws -> (ModelContext, PullRequest, User) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        // When viewer == author, reuse the single User to avoid colliding on
        // User.login's unique attribute.
        let viewerUser = User(login: viewer, name: nil, avatarURL: nil)
        ctx.insert(viewerUser)
        let authorUser: User
        if author == viewer {
            authorUser = viewerUser
        } else {
            authorUser = User(login: author, name: nil, avatarURL: nil)
            ctx.insert(authorUser)
        }
        let repo = Repo(owner: "oreilly", name: "spark-ios")
        ctx.insert(repo)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pr = PullRequest(id: "PR_1", number: 1, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: now, updatedAt: now, author: authorUser, repo: repo)
        ctx.insert(pr)
        try ctx.save()
        return (ctx, pr, viewerUser)
    }

    private func makeReviewComment(in pr: PullRequest, ctx: ModelContext,
                                   id: String, author: User, body: String = "x",
                                   parentReview: Int? = 1, inReplyTo: String? = nil,
                                   isDone: Bool = false, createdAt: Date = .distantPast) -> ReviewComment {
        let c = ReviewComment(id: id, parentReviewIntegerID: parentReview,
                              inReplyToID: inReplyTo, author: author,
                              body: body, path: "F.swift", line: 1, diffHunk: "@@",
                              createdAt: createdAt, isSeen: false, pullRequest: pr)
        c.isDone = isDone
        ctx.insert(c)
        return c
    }

    // MARK: - Resolution rules

    @Test func isResolved_emptyThread_vacuouslyTrue() {
        let t = PRTracker.Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func isResolved_onlyMineMessages_true() {
        let me = User(login: "alex", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: me, createdAt: .distantPast, body: "x",
                                isMine: true, isDone: false, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = PRTracker.Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func isResolved_oneOpenNonMine_false() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                                isMine: false, isDone: false, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = PRTracker.Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == false)
    }

    @Test func isResolved_allNonMineDone_true() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                                isMine: false, isDone: true, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = PRTracker.Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func openCount_countsOnlyNonMineNotDone() {
        let me = User(login: "alex", name: nil, avatarURL: nil)
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let messages = [
            ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m1")),
            ThreadMessage(id: "m2", actor: me, createdAt: .distantPast, body: "y",
                          isMine: true, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m2")),
            ThreadMessage(id: "m3", actor: other, createdAt: .distantPast, body: "z",
                          isMine: false, isDone: true, isNew: false,
                          underlying: .timelineEvent(eventID: "m3")),
        ]
        let t = PRTracker.Thread(id: "t1", kind: .prComment, location: "D", kindLabel: nil, messages: messages)
        #expect(TodoHelpers.openCount(t) == 1)
    }

    @Test func hasNew_requiresAllThree() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let t1 = PRTracker.Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: true,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t1) == true)
        let t2 = PRTracker.Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: true, isNew: true,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t2) == false)
        let t3 = PRTracker.Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t3) == false)
    }

    // MARK: - PR-level aggregates

    @Test func todoCounts_emptyPR_zeroes() throws {
        let (_, pr, viewer) = try makePR()
        let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(counts == TodoCounts(total: 0, done: 0, open: 0, openMessages: 0))
    }

    @Test func todoCounts_mixedThreads() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other, parentReview: 1)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC2", author: other, parentReview: 1, inReplyTo: "RC1")
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC3", author: other, parentReview: 2)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC4", author: other, parentReview: 3, isDone: true)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let counts = TodoHelpers.todoCounts(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(counts.total == 3)
        #expect(counts.done == 1)
        #expect(counts.open == 2)
        #expect(counts.openMessages == 3)
    }

    @Test func ballInMyCourt_othersPR_noOpenMessages_false() throws {
        let (_, pr, viewer) = try makePR()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    @Test func ballInMyCourt_othersPR_oneOpenMessage_true() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        #expect(TodoHelpers.ballInMyCourt(prFresh, viewerLogin: viewer.login, lastSeenAt: nil) == true)
    }

    @Test func ballInMyCourt_mergedPR_alwaysFalse() throws {
        let (ctx, pr, viewer) = try makePR()
        pr.state = .merged
        try ctx.save()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    @Test func ballInMyCourt_closedPR_alwaysFalse() throws {
        // Even with open non-mine messages, a closed PR can't be ball-in-court.
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other)
        pr.state = .closed
        try ctx.save()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    // MARK: - Thread derivation

    @Test func threads_buildsReviewCommentChain() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other,
                              parentReview: 1, createdAt: Date(timeIntervalSince1970: 1000))
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC2", author: other,
                              parentReview: 1, inReplyTo: "RC1",
                              createdAt: Date(timeIntervalSince1970: 2000))
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.count == 1)
        #expect(ts[0].kind == .reviewComment)
        #expect(ts[0].messages.count == 2)
        #expect(ts[0].messages[0].id == "RC1")
        #expect(ts[0].messages[1].id == "RC2")
    }

    @Test func threads_buildsPRCommentThread() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_1", type: .comment, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "x")
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.count == 1)
        #expect(ts[0].kind == .prComment)
        #expect(ts[0].messages.count == 1)
        #expect(ts[0].location == "Discussion")
    }

    @Test func threads_buildsReviewSummaryThread_approved() throws {
        // A .review event with body "LGTM" + state .approved becomes a thread
        // labeled "Approved".
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_REV", type: .review, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "LGTM",
                                  reviewState: .approved)
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.count == 1)
        #expect(ts[0].kindLabel == "Approved")
        #expect(ts[0].messages.first?.body == "LGTM")
    }

    @Test func threads_skipsReviewEventWithEmptyBody() throws {
        // A .review event with no body shouldn't produce a thread.
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_REV", type: .review, at: .distantPast,
                                  pullRequest: pr, actor: other, body: nil,
                                  reviewState: .approved)
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.isEmpty)
    }

    @Test func ballInMyCourt_myPR_ciFailing_true() throws {
        // Viewer authored the PR; CI is red; no open comments. The author
        // still owes a fix, so ballInMyCourt should fire.
        let (_, pr, viewer) = try makePR(viewer: "alex", author: "alex")
        pr.ciFail = 2
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == true)
    }

    @Test func ballInMyCourt_othersPR_ciFailing_false() throws {
        // CI failing on someone else's PR isn't my todo.
        let (_, pr, viewer) = try makePR()  // viewer "alex", author "dan"
        pr.ciFail = 5
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    @Test func ballInMyCourt_myPR_changesRequested_true() throws {
        // Viewer authored the PR; a reviewer requested changes; no open code
        // comments. The changesRequested path of ballInMyCourt should still
        // fire because the author owes a fix.
        let (ctx, pr, viewer) = try makePR(viewer: "alex", author: "alex")
        let bob = User(login: "bob", name: nil, avatarURL: nil)
        ctx.insert(bob)
        let reviewer = Reviewer(user: bob, state: .changesRequested, pr: pr)
        ctx.insert(reviewer)
        pr.reviewers.append(reviewer)
        try ctx.save()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == true)
    }

    // MARK: - githubURL anchor construction

    @Test func githubURL_prComment_usesIssuecommentAnchor() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_1", type: .comment, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "x")
        event.numericID = 12345
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.first?.githubURL?.absoluteString == "https://github.com/oreilly/spark-ios/pull/1#issuecomment-12345")
    }

    @Test func githubURL_reviewSummary_usesPullrequestreviewAnchor() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_REV", type: .review, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "LGTM",
                                  reviewState: .approved)
        event.reviewID = 98765
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.first?.githubURL?.absoluteString == "https://github.com/oreilly/spark-ios/pull/1#pullrequestreview-98765")
    }

    @Test func githubURL_reviewComment_usesDiscussionAnchor() throws {
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let root = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other)
        root.numericID = 55555
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.first?.githubURL?.absoluteString == "https://github.com/oreilly/spark-ios/pull/1#discussion_r55555")
    }

    @Test func githubURL_nilNumericID_fallsBackToPRURL() throws {
        // A legacy row (no numericID yet) should still produce a clickable
        // URL — the bare PR page.
        let (ctx, pr, viewer) = try makePR()
        let other = User(login: "reviewer", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_1", type: .comment, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "x")
        // numericID intentionally NOT set
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.first?.githubURL?.absoluteString == "https://github.com/oreilly/spark-ios/pull/1")
    }
}
