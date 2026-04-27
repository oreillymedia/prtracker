import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct GitHubClientTests {
    private func makeClient(token: String? = "ghp_test") -> GitHubClient {
        GitHubClient(
            session: URLSession(configuration: .stubbed),
            tokenProvider: { token }
        )
    }
    private func fixture(_ name: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
    private final class BundleToken {}

    @Test func validateReturnsUser() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/user",
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: fixture("user")
            )
            let user = try await makeClient().validate()
            #expect(user.login == "alex.chen")
            #expect(user.name == "Alex Chen")
        }
    }

    @Test func validateUnauthorizedThrows() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", status: 401, body: Data())
            do {
                _ = try await makeClient().validate()
                Issue.record("expected throw")
            } catch let e as GitHubError {
                #expect(e == .unauthorized)
            } catch { Issue.record("wrong error type: \(error)") }
        }
    }
}

extension GitHubClientTests {
    @Test func listOpenPRsDecodes() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=open&sort=updated&direction=desc&per_page=50",
                status: 200, body: fixture("pulls_open"))
            let prs = try await makeClient().listOpenPRs(repo: RepoRef(owner: "oreilly", name: "spark-ios"))
            #expect(prs.count == 1)
            #expect(prs[0].number == 5107)
            #expect(prs[0].title.contains("Fetch badge"))
        }
    }

    @Test func checkRunsDecodes() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/repos/oreilly/spark-ios/commits/d4f91ee/check-runs",
                status: 200, body: fixture("check_runs"))
            let r = try await makeClient().checkRuns(repo: RepoRef(owner: "oreilly", name: "spark-ios"), ref: "d4f91ee")
            #expect(r.total_count == 12)
            #expect(r.check_runs.count == 2)
        }
    }

    @Test func rateLimitedThrows() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/user",
                status: 403,
                headers: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "1900000000"
                ],
                body: Data())
            do { _ = try await makeClient().validate(); Issue.record("expected throw") }
            catch let e as GitHubError {
                if case .rateLimited(let when) = e {
                    #expect(when.timeIntervalSince1970 == 1900000000)
                } else { Issue.record("wrong case: \(e)") }
            } catch { Issue.record("wrong type: \(error)") }
        }
    }
}

extension GitHubClientTests {
    @Test func notModifiedThrowsNotModified() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://api.github.com/user", status: 304, body: Data())
            do {
                _ = try await makeClient().validate()
                Issue.record("expected throw")
            } catch let e as GitHubError {
                #expect(e == .notModified)
            } catch { Issue.record("wrong error: \(error)") }
        }
    }

    @Test func sendsIfNoneMatchWhenEtagProvided() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(
                url: "https://api.github.com/user", status: 200,
                headers: ["ETag": "W/\"abc\""], body: fixture("user"))
            let client = GitHubClient(
                session: URLSession(configuration: .stubbed),
                tokenProvider: { "ghp_test" },
                etagProvider: { _ in "W/\"abc\"" },
                etagSink: { _,_ in }
            )
            _ = try await client.validate()
            let lastReq = StubURLProtocol.captured.last!
            #expect(lastReq.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
        }
    }
}
