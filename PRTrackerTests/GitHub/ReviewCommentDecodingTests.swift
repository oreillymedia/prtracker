import Testing
import Foundation
@testable import PRTracker

@Suite struct ReviewCommentDecodingTests {
    private final class BundleAnchor {}

    private func loadFixture() throws -> Data {
        let url = Bundle(for: BundleAnchor.self)
            .url(forResource: "pulls_5107_comments", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    @Test func decodesArrayOfThree() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        #expect(comments.count == 3)
    }

    @Test func decodesReplyLink() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        let reply = comments.first(where: { $0.id == 1002 })
        #expect(reply?.in_reply_to_id == 1001)
    }

    @Test func decodesOutdatedComment() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        let outdated = comments.first(where: { $0.id == 1003 })
        #expect(outdated?.line == nil)
        #expect(outdated?.original_line == 17)
    }
}
