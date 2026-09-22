import Testing
import Foundation
@testable import PRTracker

@Suite struct ConnectionStateTests {
    @Test func repoStoresLastSyncErrorRaw() {
        let repo = Repo(owner: "oreilly", name: "spark-ios")
        repo.lastSyncErrorRaw = String(describing: GitHubError.forbidden)

        #expect(repo.lastSyncErrorRaw == "forbidden")
    }

    @Test func viewerStateStoresTokenSummary() {
        let expiration = Date(timeIntervalSince1970: 1_900_000_000)
        let state = ViewerState()
        state.tokenType = .fineGrained
        state.tokenScopes = ["repo", "read:org"]
        state.tokenExpirationDate = expiration

        #expect(state.tokenType == .fineGrained)
        #expect(state.tokenScopes == ["repo", "read:org"])
        #expect(state.tokenExpirationDate == expiration)
    }
}
