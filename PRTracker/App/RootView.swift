import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    var body: some View {
        let signedIn = (keychain.load() != nil) && (viewerStates.first?.viewer != nil) && (viewerStates.first?.activeRepoID != nil)
        Group {
            if signedIn {
                MainView(coordinator: coordinator, onOpenSettings: { /* Settings scene wires this in Task 27 */ })
                    .task { coordinator.start() }
            } else {
                OnboardingView(keychain: keychain, client: client, onReady: {
                    coordinator.start()
                })
            }
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]
    @Query private var prs: [PullRequest]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        @Bindable var appState = appState
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)

        NavigationSplitView {
            Sidebar(
                viewer: viewer,
                repoSlug: repo?.id ?? "",
                counts: counts(viewerLogin: viewer?.login ?? ""),
                selection: $appState.activeSection,
                onOpenSettings: onOpenSettings)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                Text("Detail for #\(pr.number)") // replaced in Phase 9
            } else {
                FeedView(coordinator: coordinator)
            }
        }
    }

    private func counts(viewerLogin: String) -> [Section: Int] {
        var c: [Section: Int] = [:]
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: [], updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: [], now: .now) {
                c[s, default: 0] += 1
            }
        }
        return c
    }
}
