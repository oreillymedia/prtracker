import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct ConnectionCheckTests {
    private let repo = RepoRef(owner: "oreilly", name: "spark-ios")
    private let authorizeURL = URL(string: "https://github.com/orgs/oreillymedia/sso?authorization_request=abc")!

    private func client() -> GitHubClient {
        GitHubClient(session: URLSession(configuration: .stubbed), tokenProvider: { "ghp_test" })
    }

    private func userJSON() -> Data {
        #"{"login":"alex.chen","name":"Alex Chen","avatar_url":null}"#.data(using: .utf8)!
    }

    private func repoJSON() -> Data {
        #"{"full_name":"oreilly/spark-ios","default_branch":"main"}"#.data(using: .utf8)!
    }

    private func check(repos: [RepoRef] = []) async -> ConnectionCheckResult {
        await ConnectionCheck(client: client(), token: "ghp_test").run(repos: repos)
    }

    @Test func classicTokenMissingRepoScopeFails() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", headers: ["X-OAuth-Scopes": "read:user"], body: userJSON())
            StubURLProtocol.register(url: "https://api.github.com/user/orgs", json: "[]")

            let result = await check()
            let scope = result.items.first { $0.id == "scope" }
            #expect(scope?.status == .failure)
            #expect(scope?.message.contains("repo") == true)
            #expect(scope?.action?.url == GitHubTokenGuide.tokenURL)
        }
    }

    @Test func repoSSOHeaderOffersAuthorizeAction() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", headers: ["X-OAuth-Scopes": "repo"], body: userJSON())
            StubURLProtocol.register(url: "https://api.github.com/user/orgs", json: "[]")
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios",
                status: 403,
                headers: ["X-GitHub-SSO": "required; url=\(authorizeURL.absoluteString)"],
                body: Data())

            let result = await check(repos: [repo])
            let reachable = result.items.first { $0.id == "repo:oreilly/spark-ios:reachable" }
            #expect(reachable?.status == .failure)
            #expect(reachable?.action?.label == "Authorize")
            #expect(reachable?.action?.url == authorizeURL)
        }
    }

    @Test func partialSSOHeaderProducesOrganizationWarning() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", body: userJSON())
            StubURLProtocol.register(
                url: "https://api.github.com/user/orgs",
                headers: ["X-GitHub-SSO": "partial-results; organizations=1"],
                json: "[]")

            let result = await check()
            let sso = result.items.first { $0.id == "sso" }
            #expect(sso?.status == .warning)
            #expect(sso?.action?.url == GitHubTokenGuide.tokenURL)
        }
    }

    @Test func shortExpiryProducesWarningAndIsStored() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            let expiration = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
            StubURLProtocol.register(
                url: "https://api.github.com/user",
                headers: ["GitHub-Authentication-Token-Expiration": formatter.string(from: expiration)],
                body: userJSON())
            StubURLProtocol.register(url: "https://api.github.com/user/orgs", json: "[]")

            let result = await check()
            let expiry = result.items.first { $0.id == "expiry" }
            #expect(expiry?.status == .warning)
            #expect(result.metadata.expiration != nil)
        }
    }

    @Test func pullAndChecksProbeFailuresNameFineGrainedPermissions() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", headers: ["X-OAuth-Scopes": "repo"], body: userJSON())
            StubURLProtocol.register(url: "https://api.github.com/user/orgs", json: "[]")
            StubURLProtocol.register(url: "https://api.github.com/repos/oreilly/spark-ios", body: repoJSON())
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=open&sort=updated&direction=desc&per_page=1",
                status: 403,
                body: Data())
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/commits/main/check-runs?per_page=1",
                status: 403,
                body: Data())

            let result = await check(repos: [repo])
            let pulls = result.items.first { $0.id == "repo:oreilly/spark-ios:pulls" }
            let checks = result.items.first { $0.id == "repo:oreilly/spark-ios:checks" }
            #expect(pulls?.status == .failure)
            #expect(pulls?.message.contains("Pull requests: Read") == true)
            #expect(checks?.status == .failure)
            #expect(checks?.message.contains("Checks: Read") == true)
        }
    }
}
