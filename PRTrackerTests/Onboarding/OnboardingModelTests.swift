import Testing
import Foundation
import SwiftData
@testable import PRTracker

@MainActor
@Suite struct OnboardingModelTests {
    @Test func welcomeAlwaysContinues() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(m.canContinue(from: .welcome))
    }

    @Test func connectRequiresViewer() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(!m.canContinue(from: .connect))
        m.applyValidatedViewer(UserDTO(login: "alex", name: "Alex", avatar_url: nil))
        #expect(m.canContinue(from: .connect))
    }

    @Test func repositoriesRequireAtLeastOne() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(!m.canContinue(from: .repositories))
        #expect(m.addRepo("oreilly/spark-ios"))
        #expect(m.canContinue(from: .repositories))
    }

    @Test func addRepoRejectsDuplicatesAndGarbage() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(m.addRepo("oreilly/spark-ios"))
        #expect(!m.addRepo("oreilly/spark-ios"))   // duplicate
        #expect(!m.addRepo("garbage"))             // unparseable
        #expect(m.pending.count == 1)
    }

    @Test func removeRepo() {
        let m = OnboardingModel(mode: .firstRun)
        _ = m.addRepo("a/b"); _ = m.addRepo("c/d")
        m.removeRepo(id: "a/b")
        #expect(m.pending.map(\.id) == ["c/d"])
    }

    @Test func commitFirstRunInsertsViewerAndRepos() throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let m = OnboardingModel(mode: .firstRun)
        m.applyValidatedViewer(UserDTO(login: "alex", name: "Alex", avatar_url: nil))
        _ = m.addRepo("oreilly/spark-ios", level: .everything)
        _ = m.addRepo("oreilly/mobile-lot", level: .none)

        m.commit(into: ctx)

        let repos = try ctx.fetch(FetchDescriptor<Repo>()).sorted { $0.id < $1.id }
        #expect(repos.map(\.id) == ["oreilly/mobile-lot", "oreilly/spark-ios"])
        #expect(repos.first { $0.id == "oreilly/spark-ios" }?.notificationLevel == .everything)
        #expect(repos.first { $0.id == "oreilly/mobile-lot" }?.notificationLevel == NotificationLevel.none)
        #expect(repos.allSatisfy { $0.isEnabled })
        let vs = try ctx.fetch(FetchDescriptor<ViewerState>())
        #expect(vs.first?.viewer?.login == "alex")
    }

    @Test func reconfigureReconcilesKeepsRemovesAdds() throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        // Existing store: two repos, one disabled, with a PR under "keep".
        let viewer = User(login: "alex"); ctx.insert(viewer)
        let vs = ViewerState(viewer: viewer); ctx.insert(vs)
        let keep = Repo(owner: "oreilly", name: "keep"); keep.notificationLevel = .personal; ctx.insert(keep)
        let drop = Repo(owner: "oreilly", name: "drop", isEnabled: false); ctx.insert(drop)
        ctx.insert(PullRequest(id: "PR1", number: 1, title: "t", state: .open,
                               branchHead: "h", branchBase: "main", headSha: "s",
                               openedAt: .now, updatedAt: .now, author: viewer, repo: keep))
        try ctx.save()

        let m = OnboardingModel(mode: .reconfigure)
        m.seed(from: ctx)
        #expect(Set(m.pending.map(\.id)) == ["oreilly/keep", "oreilly/drop"])

        m.pending.removeAll { $0.id == "oreilly/drop" }
        if let i = m.pending.firstIndex(where: { $0.id == "oreilly/keep" }) { m.pending[i].level = .everything }
        _ = m.addRepo("oreilly/new", level: .personal)

        m.commit(into: ctx)

        let repos = try ctx.fetch(FetchDescriptor<Repo>())
        #expect(Set(repos.map(\.id)) == ["oreilly/keep", "oreilly/new"])
        let kept = repos.first { $0.id == "oreilly/keep" }
        #expect(kept?.notificationLevel == .everything)
        #expect(kept?.pullRequests.count == 1)          // PR preserved
        #expect((repos.first { $0.id == "oreilly/new" })?.isEnabled == true)
    }
}
