import SwiftUI
import SwiftData

struct PRDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query private var viewerStates: [ViewerState]
    let pr: PullRequest
    let viewer: User?
    let client: GitHubClient
    let syncActor: SyncActor

    @State private var loadError: GitHubError?
    @State private var isLoading: Bool = false
    @State private var inspectorPresented: Bool = true

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    private var todoCounts: TodoCounts {
        TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    private var ciFailedForMe: Bool {
        pr.state == .open && pr.author.login == viewerLogin && pr.ciFail > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            MailDetailHeader(pr: pr, todoCounts: todoCounts, ciFailedForMe: ciFailedForMe)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        Text("Couldn't load timeline: \(String(describing: loadError)). Click refresh to retry.")
                            .foregroundStyle(Tokens.changes).padding(8)
                            .background(Tokens.changes.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    ThreadsView(pr: pr, viewerLogin: viewerLogin, syncActor: syncActor)
                }.padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(pr.title)
        .inspector(isPresented: $inspectorPresented) {
            DetailRightRail(pr: pr)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await loadTimeline() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(isLoading)

                Button {
                    if let url = URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)") {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "globe")
                }
                .help("Open on GitHub")
            }
            ToolbarItem {
                Button { inspectorPresented.toggle() } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle details")
            }
        }
        .task(id: pr.id) {
            await loadTimeline()
        }
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
            async let rc = client.reviewComments(repo: ref, number: number)
            let (tItems, reviewDTOs, _, detail, checks, reviewComments) = try await (t, r, c, d, ck, rc)
            try await syncActor.upsertTimeline(prID: prID, items: tItems)
            try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs)
            try await syncActor.upsertReviewComments(prID: prID, fromDTOs: reviewComments)
            try await syncActor.updatePRStatistics(prID: prID, dto: detail)
            try await syncActor.upsertCIChecks(prID: prID, dto: checks)
            loadError = nil
        } catch is CancellationError {
            // .task replaced before we finished; new task will reload — don't surface.
        } catch let e as GitHubError {
            // Some networking layers wrap cancellation as a `.network(message: "cancelled")`.
            if case .network(let msg) = e, msg.lowercased().contains("cancel") { return }
            loadError = e
        } catch {
            if error.localizedDescription.lowercased().contains("cancel") { return }
            loadError = .network(message: error.localizedDescription)
        }
    }
}
