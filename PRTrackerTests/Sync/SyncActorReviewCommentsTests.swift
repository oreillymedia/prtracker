import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct SyncActorReviewCommentsTests {
    private func setup() throws -> (ModelContainer, Repo, PullRequest) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let user = User(login: "alex.chen", name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(user); ctx.insert(repo)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let pr = PullRequest(id: "PR_5107", number: 5107, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: t, updatedAt: t, author: user, repo: repo)
        ctx.insert(pr)
        try ctx.save()
        return (container, repo, pr)
    }

    private func sampleDTO(id: Int = 1001, reviewID: Int? = 9001, replyTo: Int? = nil,
                           body: String = "Body", line: Int? = 42, origLine: Int? = 42) -> ReviewCommentDTO {
        let json = """
        {"id":\(id),"node_id":"PRRC_\(id)","pull_request_review_id":\(reviewID.map(String.init) ?? "null"),
         "in_reply_to_id":\(replyTo.map(String.init) ?? "null"),
         "user":{"login":"alex.chen","node_id":"U_alex"},
         "body":"\(body)","path":"Sources/Player.swift",
         "line":\(line.map(String.init) ?? "null"),"original_line":\(origLine.map(String.init) ?? "null"),
         "diff_hunk":"@@ ...\\n func play(){}",
         "created_at":"2026-05-19T15:00:00Z","updated_at":"2026-05-19T15:00:00Z"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(ReviewCommentDTO.self, from: json.data(using: .utf8)!)
    }

    @Test func upsertInsertsNew() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO()])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.count == 1)
        #expect(comments[0].id == "PRRC_1001")
        #expect(comments[0].parentReviewIntegerID == 9001)
        #expect(comments[0].line == 42)
    }

    @Test func upsertUpdatesExistingByID() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Original")])
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Edited")])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.count == 1)
        #expect(comments[0].body == "Edited")
    }

    @Test func upsertPreservesIsSeen() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO()])
        let ctx = ModelContext(container)
        let c = try ctx.fetch(FetchDescriptor<ReviewComment>()).first!
        c.isSeen = true
        try ctx.save()
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Edited")])
        let ctx2 = ModelContext(container)
        let c2 = try ctx2.fetch(FetchDescriptor<ReviewComment>()).first!
        #expect(c2.isSeen == true)
    }

    @Test func upsertPurgesStale() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002)])
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(id: 1001)])
        let ctx = ModelContext(container)
        let ids = try ctx.fetch(FetchDescriptor<ReviewComment>()).map(\.id)
        #expect(ids == ["PRRC_1001"])
    }

    @Test func upsertFallsBackToOriginalLineWhenLineNil() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(line: nil, origLine: 17)])
        let ctx = ModelContext(container)
        let c = try ctx.fetch(FetchDescriptor<ReviewComment>()).first!
        #expect(c.line == 17)
    }

    @Test func upsertSetsInReplyToID() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002, replyTo: 1001)])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>()).sorted { $0.id < $1.id }
        #expect(comments[0].inReplyToID == nil)
        #expect(comments[1].inReplyToID == "PRRC_1001")
    }
}
