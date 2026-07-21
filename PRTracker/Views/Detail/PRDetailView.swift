import SwiftUI
import SwiftData

struct PRDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query private var viewerStates: [ViewerState]
    let pr: PullRequest
    let viewer: User?
    let coordinator: SyncCoordinator
    let syncActor: SyncActor

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
            MailDetailHeader(pr: pr, todoCounts: todoCounts, ciFailedForMe: ciFailedForMe, isUpdating: coordinator.isRefreshingDetail)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError = coordinator.lastDetailError {
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
                Button { coordinator.refreshSelectedPRNow() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(coordinator.isRefreshingDetail)

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
            // Debounce: when sweeping selection quickly through the source list,
            // registering each transient PR would fire a burst of fetches.
            // .task(id:) cancels this when the selection moves on, so only a
            // settled selection (held ~300ms) becomes the coordinator's priority
            // PR. The coordinator then keeps it fresh on its own interval and
            // reflects progress via `isRefreshingDetail`.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            coordinator.selectPR(prID: pr.id, ref: RepoRef(owner: pr.repo.owner, name: pr.repo.name), number: pr.number)
        }
        .onDisappear { coordinator.clearPRSelection() }
    }
}
