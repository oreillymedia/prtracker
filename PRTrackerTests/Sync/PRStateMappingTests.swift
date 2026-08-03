import Testing
import Foundation
@testable import PRTracker

@Suite struct PRStateMappingTests {
    private func pullDTO(state: String = "open", draft: Bool = false, mergedAt: String = "null") -> PullRequestDTO {
        let json = """
        {"node_id":"PR_1","number":1,"title":"T","state":"\(state)","draft":\(draft),
         "merged_at":\(mergedAt),"created_at":"2026-04-21T09:14:00Z","updated_at":"2026-04-23T10:47:00Z",
         "user":{"login":"alex.chen","id":1,"name":null,"avatar_url":null},
         "head":{"ref":"alex/x","sha":"d4f91ee"},"base":{"ref":"main","sha":"deadbeef"},
         "additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean","labels":[],"requested_reviewers":[]}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(PullRequestDTO.self, from: json.data(using: .utf8)!)
    }

    /// GitHub spreads PR state across `state`, `draft`, and `merged_at`; both the
    /// list upsert and the single-PR detail patch route through this mapping, so
    /// the two writers can't disagree about whether a PR is still open.
    @Test func mapsGitHubsThreeStateFieldsToOurs() {
        #expect(SyncActor.prState(from: pullDTO()) == .open)
        #expect(SyncActor.prState(from: pullDTO(state: "closed")) == .closed)
        #expect(SyncActor.prState(from: pullDTO(state: "closed", mergedAt: "\"2026-04-24T10:00:00Z\"")) == .merged)
        #expect(SyncActor.prState(from: pullDTO(draft: true)) == .draft)
    }
}
