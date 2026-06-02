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
}
