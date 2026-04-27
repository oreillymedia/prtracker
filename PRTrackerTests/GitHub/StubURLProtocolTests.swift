import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct StubURLProtocolTests {
    @Test func roundtrip() async throws {
        try await StubURLProtocol.withExclusiveStubs {
            StubURLProtocol.register(url: "https://example.com/x", status: 200, json: #"{"ok":true}"#)
            let session = URLSession(configuration: .stubbed)
            let (data, resp) = try await session.data(from: URL(string: "https://example.com/x")!)
            #expect((resp as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        }
    }
}
