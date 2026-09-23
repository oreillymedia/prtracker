import Testing
import Foundation
import SwiftData
@testable import PRTracker

@MainActor
@Suite(.serialized) struct SyncCoordinatorTests {
    private final class BundleToken {}

    private nonisolated static func fixture(_ name: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        return try! Data(contentsOf: bundle.url(forResource: name, withExtension: "json")!)
    }

    @Test func transientFailureDuringPRPollingIsStoredOnRepo() async throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios")
        ctx.insert(repo)
        try ctx.save()

        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=open&sort=updated&direction=desc&per_page=50",
                body: Self.fixture("pulls_open"))
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=closed&sort=updated&direction=desc&per_page=20",
                json: "[]")

            let client = GitHubClient(session: URLSession(configuration: .stubbed), tokenProvider: { "ghp_test" })
            let coordinator = SyncCoordinator(client: client, syncActor: SyncActor(modelContainer: container), modelContainer: container)
            await coordinator.refresh()

            let refreshed = try ModelContext(container).fetch(FetchDescriptor<Repo>()).first
            #expect(refreshed?.lastSyncErrorRaw?.contains("network") == true)
            if case .network = coordinator.lastSyncError {
                #expect(Bool(true))
            } else {
                Issue.record("expected a network error")
            }
        }
    }

    @Test func permissionGapDuringPRPollingIsStoredOnRepo() async throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios")
        ctx.insert(repo)
        try ctx.save()

        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=open&sort=updated&direction=desc&per_page=50",
                body: Self.fixture("pulls_open"))
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=closed&sort=updated&direction=desc&per_page=20",
                json: "[]")
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/commits/d4f91ee/check-runs",
                status: 403,
                body: Data())

            let client = GitHubClient(session: URLSession(configuration: .stubbed), tokenProvider: { "ghp_test" })
            let coordinator = SyncCoordinator(client: client, syncActor: SyncActor(modelContainer: container), modelContainer: container)
            await coordinator.refresh()

            let refreshed = try ModelContext(container).fetch(FetchDescriptor<Repo>()).first
            #expect(refreshed?.lastSyncErrorRaw == "forbidden")
            #expect(coordinator.lastSyncError == .forbidden)
        }
    }
}
