import Testing
import Foundation
@testable import PRTracker

@Suite struct GitHubErrorTests {
    @Test func userFacingMappingCoversEveryErrorCase() {
        let errors: [GitHubError] = [
            .unauthorized,
            .forbidden,
            .ssoRequired(authorizeURL: URL(string: "https://github.com/orgs/oreillymedia/sso")!),
            .repoNotFound,
            .rateLimited(resetAt: Date(timeIntervalSince1970: 1_900_000_000)),
            .network(message: "offline"),
            .decoding(message: "bad payload"),
            .notModified,
        ]

        for error in errors {
            let presentation = error.userFacing
            #expect(!presentation.title.isEmpty)
            #expect(!presentation.detail.isEmpty)
        }
    }

    @Test func ssoPresentationOffersAuthorizeAction() {
        let url = URL(string: "https://github.com/orgs/oreillymedia/sso")!
        let presentation = GitHubError.ssoRequired(authorizeURL: url).userFacing

        #expect(presentation.action?.label == "Authorize")
        #expect(presentation.action?.url == url)
    }

    @Test func permissionGapErrorsSurfacePerRepo() {
        #expect(GitHubError.forbidden.isPermissionGap)
        #expect(GitHubError.repoNotFound.isPermissionGap)
        #expect(GitHubError.ssoRequired(authorizeURL: URL(string: "https://example.com")!).isPermissionGap)
        #expect(!GitHubError.network(message: "offline").isPermissionGap)
    }
}
