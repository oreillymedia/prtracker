import Testing
import Foundation
@testable import PRTracker

@Suite struct OpenListCompletenessTests {
    private func pullDTO(number: Int) -> PullRequestDTO {
        let json = """
        {"node_id":"PR_\(number)","number":\(number),"title":"T","state":"open","draft":false,
         "merged_at":null,"created_at":"2026-04-21T09:14:00Z","updated_at":"2026-04-23T10:47:00Z",
         "user":{"login":"alex.chen","id":1,"name":null,"avatar_url":null},
         "head":{"ref":"alex/x","sha":"d4f91ee"},"base":{"ref":"main","sha":"deadbeef"},
         "additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean","labels":[],"requested_reviewers":[]}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(PullRequestDTO.self, from: json.data(using: .utf8)!)
    }

    /// `listOpenPRs` fetches a single page, so a response of exactly the page size
    /// may be page 1 of several. Only a short page is the repo's whole open set —
    /// trusting a full one would close the stalest open PRs, which sort last under
    /// `updated desc` and fall off page 1.
    @Test func onlyAShortPageCountsAsComplete() {
        let fullPage = (0..<GitHubClient.openPRPageSize).map { pullDTO(number: $0) }
        #expect(GitHubClient.openListIsComplete(fullPage) == false)
        #expect(GitHubClient.openListIsComplete(Array(fullPage.dropLast())) == true)
        #expect(GitHubClient.openListIsComplete([]) == true)
    }
}
