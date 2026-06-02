import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import PRTracker

@Suite struct NotificationDispatcherTests {
    private func setup(level: NotificationLevel = .personal, viewerLogin: String = "alex") throws -> (ModelContainer, Repo, ViewerState) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(repo)
        let viewer = User(login: viewerLogin)
        ctx.insert(viewer)
        let vs = ViewerState(viewer: viewer, activeRepoID: repo.id)
        vs.notificationLevel = level
        ctx.insert(vs)
        try ctx.save()
        return (container, repo, vs)
    }

    private func seedBaseline(for pr: PullRequest, ctx: ModelContext) {
        ctx.insert(NotificationLog(id: "opened_\(pr.id)", kind: "opened", notifiedAt: .now, pullRequest: pr))
        ctx.insert(NotificationLog(id: "push_\(pr.id)_\(pr.headSha)", kind: "push", notifiedAt: .now, pullRequest: pr))
        ctx.insert(NotificationLog(id: "state_\(pr.id)_\(pr.state.rawValue)", kind: "state_change", notifiedAt: .now, pullRequest: pr))
    }

    @Test func levelNoneShortCircuits() async throws {
        let (container, repo, _) = try setup(level: .none)
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func authDeniedShortCircuits() async throws {
        let (container, repo, _) = try setup()
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .denied),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func appFrontmostShortCircuits() async throws {
        let (container, repo, _) = try setup()
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: true))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func singleNewIssueCommentFires() async throws {
        let (container, repo, _) = try setup(level: .everything)
        let ctx = ModelContext(container)
        let author = User(login: "iris")
        ctx.insert(author)
        let pr = PullRequest(id: "PR_42", number: 42, title: "Add login",
                             state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: .now, updatedAt: .now,
                             author: author, repo: repo)
        ctx.insert(pr)
        seedBaseline(for: pr, ctx: ctx)
        let evt = TimelineEvent(id: "IC_1", type: .comment, at: .now,
                                pullRequest: pr, actor: author, body: "Looks good")
        ctx.insert(evt)
        try ctx.save()

        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)

        #expect(poster.posted.count == 1)
        #expect(poster.posted[0].title == "\(repo.id) #42")
        #expect(poster.posted[0].body.contains("iris"))
        #expect(poster.posted[0].body.contains("Looks good"))

        let logs = try ctx.fetch(FetchDescriptor<NotificationLog>())
        #expect(logs.count == 4)
        #expect(logs.contains(where: { $0.id == "comment_IC_1" }))
    }

    @Test func idempotentReprocessing() async throws {
        let (container, repo, _) = try setup(level: .everything)
        let ctx = ModelContext(container)
        let author = User(login: "iris")
        ctx.insert(author)
        let pr = PullRequest(id: "PR_42", number: 42, title: "T",
                             state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: .now, updatedAt: .now, author: author, repo: repo)
        ctx.insert(pr)
        seedBaseline(for: pr, ctx: ctx)
        ctx.insert(TimelineEvent(id: "IC_1", type: .comment, at: .now,
                                 pullRequest: pr, actor: author, body: "hi"))
        try ctx.save()

        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        await dispatcher.process(repoID: repo.id)

        #expect(poster.posted.count == 1)
    }

    @Test func selfActionDoesNotFire() async throws {
        let (container, repo, _) = try setup(level: .everything)
        let ctx = ModelContext(container)
        let me = (try ctx.fetch(FetchDescriptor<ViewerState>())).first!.viewer!
        let pr = PullRequest(id: "PR_43", number: 43, title: "T",
                             state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: .now, updatedAt: .now, author: me, repo: repo)
        ctx.insert(pr)
        seedBaseline(for: pr, ctx: ctx)
        ctx.insert(TimelineEvent(id: "IC_X", type: .comment, at: .now,
                                 pullRequest: pr, actor: me, body: "self"))
        try ctx.save()

        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func multipleEventsOnOnePRAggregate() async throws {
        let (container, repo, _) = try setup(level: .everything)
        let ctx = ModelContext(container)
        let author = User(login: "iris")
        ctx.insert(author)
        let pr = PullRequest(id: "PR_50", number: 50, title: "Refactor sync",
                             state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: .now, updatedAt: .now, author: author, repo: repo)
        ctx.insert(pr)
        seedBaseline(for: pr, ctx: ctx)
        ctx.insert(TimelineEvent(id: "IC_1", type: .comment, at: .now, pullRequest: pr, actor: author, body: "one"))
        ctx.insert(TimelineEvent(id: "IC_2", type: .comment, at: .now, pullRequest: pr, actor: author, body: "two"))
        ctx.insert(CIRun(checkRunID: 999, name: "build", state: .fail, pr: pr))
        try ctx.save()

        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)

        #expect(poster.posted.count == 1)
        #expect(poster.posted[0].body == "3 updates on 'Refactor sync'")

        let logs = (try ctx.fetch(FetchDescriptor<NotificationLog>())).map(\.id)
        #expect(logs.contains("comment_IC_1"))
        #expect(logs.contains("comment_IC_2"))
        #expect(logs.contains("ci_999"))
    }

    @Test func backfillWritesLogRowsButPostsNothing() async throws {
        let (container, repo, _) = try setup(level: .personal)
        let ctx = ModelContext(container)
        let author = User(login: "iris")
        ctx.insert(author)
        let pr = PullRequest(id: "PR_60", number: 60, title: "X",
                             state: .open, branchHead: "h", branchBase: "main", headSha: "sha1",
                             openedAt: .now, updatedAt: .now, author: author, repo: repo)
        ctx.insert(pr)
        ctx.insert(TimelineEvent(id: "IC_A", type: .comment, at: .now, pullRequest: pr, actor: author, body: "a"))
        ctx.insert(CIRun(checkRunID: 111, name: "build", state: .fail, pr: pr))
        try ctx.save()

        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.backfillSilentBaseline()

        #expect(poster.posted.isEmpty)
        let logs = (try ctx.fetch(FetchDescriptor<NotificationLog>())).map(\.id)
        #expect(logs.contains("comment_IC_A"))
        #expect(logs.contains("ci_111"))
        #expect(logs.contains("opened_PR_60"))
        #expect(logs.contains("push_PR_60_sha1"))

        // A subsequent process() must post nothing.
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }
}
