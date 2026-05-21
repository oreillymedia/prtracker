import SwiftUI

struct PRDetailView: View {
    let pr: PullRequest
    let viewer: User?
    let client: GitHubClient
    let syncActor: SyncActor

    @State private var loadError: GitHubError?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let loadError {
                            Text("Couldn't load timeline: \(String(describing: loadError)). Click refresh to retry.")
                                .foregroundStyle(Tokens.changes).padding(8)
                                .background(Tokens.changes.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        TimelineColumn(events: pr.timeline,
                            onTapEvent: { e in Task { try? await syncActor.setSeen(eventID: e.id, isSeen: !e.isSeen) } },
                            onMarkUpToHere: { e in Task { try? await syncActor.setSeenUpTo(prID: pr.id, throughEventID: e.id) } })
                        QuickReply(viewer: viewer)
                    }.padding(20)
                }
                DetailRightRail(pr: pr,
                    onMarkUnread: { Task { try? await syncActor.setLastReadAt(prID: pr.id, date: nil) } })
            }
        }
        .task(id: pr.id) {
            await loadTimeline()
            try? await syncActor.setSeenForPR(prID: pr.id, isSeen: true)
            try? await syncActor.setLastReadAt(prID: pr.id, date: .now)
        }
    }

    @ViewBuilder
    private var header: some View {
        MailDetailHeader(
            pr: pr,
            isRefreshing: isLoading,
            lastUpdatedAt: pr.updatedAt,
            onRefresh: { Task { await loadTimeline() } }
        )
    }

    private func loadTimeline() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let ref = RepoRef(owner: pr.repo.owner, name: pr.repo.name)
        let number = pr.number
        let prID = pr.id
        let headSha = pr.headSha
        do {
            async let t = client.timeline(repo: ref, number: number)
            async let r = client.reviews(repo: ref, number: number)
            async let c = client.issueComments(repo: ref, number: number)
            async let d = client.pullRequestDetail(repo: ref, number: number)
            async let ck = client.checkRuns(repo: ref, ref: headSha)
            let (tItems, reviewDTOs, _, detail, checks) = try await (t, r, c, d, ck)
            try await syncActor.upsertTimeline(prID: prID, items: tItems)
            try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs)
            try await syncActor.updatePRStatistics(prID: prID, dto: detail)
            try await syncActor.upsertCIChecks(prID: prID, dto: checks)
            loadError = nil
        } catch let e as GitHubError {
            loadError = e
        } catch {
            loadError = .network(message: error.localizedDescription)
        }
    }
}
