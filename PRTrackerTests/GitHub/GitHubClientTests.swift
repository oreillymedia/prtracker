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
        // Xcode test bundle — find the resource by walking from the test bundle.
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
    private final class BundleToken {}

    @Test func validateReturnsUser() async throws {
        StubURLProtocol.reset()
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

    @Test func validateUnauthorizedThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.register(url: "https://api.github.com/user", status: 401, body: Data())
        do {
            _ = try await makeClient().validate()
            Issue.record("expected throw")
        } catch let e as GitHubError {
            #expect(e == .unauthorized)
        } catch { Issue.record("wrong error type: \(error)") }
    }
}
