import Testing
import Foundation
@testable import PRTracker

@Suite struct GitHubTokenMetadataTests {
    @Test func identifiesTokenTypeScopesAndExpiration() {
        let metadata = GitHubTokenMetadata(
            token: "ghp_example",
            headers: [
                "x-oauth-scopes": "repo, read:org",
                "github-authentication-token-expiration": "2030-01-02 03:04:05 UTC",
            ])

        #expect(metadata.type == .classic)
        #expect(metadata.scopes == ["repo", "read:org"])
        #expect(metadata.expiration == Date(timeIntervalSince1970: 1893553445))
    }

    @Test func detectsFineGrainedTokenWithoutClassicScopes() {
        let metadata = GitHubTokenMetadata(token: "github_pat_example", headers: [:])

        #expect(metadata.type == .fineGrained)
        #expect(metadata.scopes.isEmpty)
        #expect(metadata.expiration == nil)
    }

    @Test func trimsPastedToken() {
        #expect(GitHubTokenMetadata.normalizedToken(" \n ghp_example \t") == "ghp_example")
    }
}
