import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct GitHubClientMetadataTests {
    private final class BundleToken {}

    @Test func validateReturnsResponseHeaders() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/user",
                status: 200,
                headers: [
                    "X-OAuth-Scopes": "repo, read:org",
                    "GitHub-Authentication-Token-Expiration": "2030-01-02 03:04:05 UTC",
                ],
                body: #"{"login":"alex.chen","name":"Alex Chen","avatar_url":null}"#.data(using: .utf8)!
            )

            let client = GitHubClient(
                session: URLSession(configuration: .stubbed),
                tokenProvider: { "ghp_test" }
            )
            let response = try await client.validateWithMetadata()

            #expect(response.value.login == "alex.chen")
            #expect(response.headers["X-OAuth-Scopes"] == "repo, read:org")
            #expect(response.headers["GitHub-Authentication-Token-Expiration"] == "2030-01-02 03:04:05 UTC")
        }
    }

    @Test func ssoRequiredHeaderBecomesAuthorizeError() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            let authorizeURL = "https://github.com/orgs/oreillymedia/sso?authorization_request=abc"
            StubURLProtocol.register(
                url: "https://api.github.com/user",
                status: 403,
                headers: ["X-GitHub-SSO": "required; url=\(authorizeURL)"],
                body: Data()
            )

            let client = GitHubClient(
                session: URLSession(configuration: .stubbed),
                tokenProvider: { "ghp_test" }
            )

            do {
                _ = try await client.validate()
                Issue.record("expected SSO error")
            } catch let error as GitHubError {
                #expect(error == .ssoRequired(authorizeURL: URL(string: authorizeURL)!))
            } catch {
                Issue.record("wrong error type: \(error)")
            }
        }
    }
}
