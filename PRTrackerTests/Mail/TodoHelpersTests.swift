import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct TodoHelpersTests {
    // MARK: - Fixture builder

    /// Returns a persistent container plus a live ModelContext (kept alive by the tuple),
    /// plus the PR and viewer user — all from the same context so callers can add to them.
    private func makePR(viewer: String = "alex", author: String = "dan",
                        reviewState: ReviewState? = nil) throws -> (ModelContext, PullRequest, User) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let viewerUser = User(login: viewer, name: nil, avatarURL: nil)
        let authorUser = User(login: author, name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(viewerUser); ctx.insert(authorUser); ctx.insert(repo)
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
}
