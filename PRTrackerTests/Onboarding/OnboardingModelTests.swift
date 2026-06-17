import Testing
import Foundation
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
}
