import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct SyncActorTests {
    private func setup() throws -> (ModelContainer, Repo) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(repo)
        try ctx.save()
        return (container, repo)
    }

    private func samplePullDTO(number: Int = 5107, head: String = "d4f91ee") -> PullRequestDTO {
        let json = """
        {"node_id":"PR_\(number)","number":\(number),"title":"T","state":"open","draft":false,
         "merged_at":null,"created_at":"2026-04-21T09:14:00Z","updated_at":"2026-04-23T10:47:00Z",
         "user":{"login":"alex.chen","id":1,"name":null,"avatar_url":null},
         "head":{"ref":"alex/x","sha":"\(head)"},"base":{"ref":"main","sha":"deadbeef"},
         "additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean","labels":[],"requested_reviewers":[]}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(PullRequestDTO.self, from: json.data(using: .utf8)!)
    }

    @Test func upsertInsertsNewPR() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs.count == 1)
        #expect(prs[0].number == 5107)
        #expect(prs[0].author.login == "alex.chen")
    }

    @Test func upsertReusesUserByLogin() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO(number: 1), samplePullDTO(number: 2)], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let users = try ctx.fetch(FetchDescriptor<User>())
        #expect(users.count == 1)
        #expect(users[0].login == "alex.chen")
    }

    @Test func upsertPreservesIsSeenOnExistingTimelineEvent() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        try await actor.upsertTimeline(prID: "PR_5107", items: [
            TimelineItemDTO(event: "commented", id: 1, node_id: "TE_1",
                            actor: UserDTO(login: "iris", name: nil, avatar_url: nil),
                            created_at: Date(timeIntervalSince1970: 1700_000_000),
                            body: "hi", sha: nil, state: nil)
        ])
        try await actor.setSeen(eventID: "TE_1", isSeen: true)
        try await actor.upsertTimeline(prID: "PR_5107", items: [
            TimelineItemDTO(event: "commented", id: 1, node_id: "TE_1",
                            actor: UserDTO(login: "iris", name: nil, avatar_url: nil),
                            created_at: Date(timeIntervalSince1970: 1700_000_000),
                            body: "hi (edited)", sha: nil, state: nil)
        ])
        let ctx = ModelContext(container)
        let events = try ctx.fetch(FetchDescriptor<TimelineEvent>())
        #expect(events.count == 1)
        #expect(events[0].isSeen == true)
        #expect(events[0].body == "hi (edited)")
    }

    @Test func openPRMissingFromResponseIsClosed() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        try await actor.upsertPullRequests([], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs.count == 1)
        #expect(prs[0].state == .closed)
    }

    @Test func newHeadShaClearsCIChecks() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO(head: "sha1")], inRepoID: repo.id)
        try await actor.upsertCIChecks(prID: "PR_5107", dto: CheckRunsResponseDTO(
            total_count: 1, check_runs: [CheckRunDTO(name: "Build", status: "completed", conclusion: "success", started_at: nil, completed_at: nil)]))
        try await actor.upsertPullRequests([samplePullDTO(head: "sha2")], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs[0].ciChecks.count == 0)
        #expect(prs[0].headSha == "sha2")
    }
}
