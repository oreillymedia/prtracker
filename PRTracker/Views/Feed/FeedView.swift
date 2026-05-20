import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]

    let coordinator: SyncCoordinator
    @State private var collapsed: [Section: Bool] = [:]
    @State private var mentionedIDs: Set<String> = []

    var body: some View {
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)
        let viewerLogin = viewer?.login ?? ""
        let buckets = grouped(viewerLogin: viewerLogin)
        let activeSection = appState.activeFilter.section

        VStack(spacing: 0) {
            FeedToolbar(
                repoSlug: repo?.id ?? "",
                lastSyncAt: coordinator.lastSyncAt,
                isSyncing: coordinator.isSyncing,
                lastError: coordinator.lastSyncError,
                onRefresh: { Task { await coordinator.refresh() } })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let activeSection {
                        ForEach(buckets[activeSection] ?? []) { pr in
                            PRCardView(pr: pr, lane: activeSection.lane, hint: hint(for: pr, section: activeSection))
                                .onTapGesture { appState.selectedPRID = pr.id }
                        }
                    } else {
                        ForEach(PRTracker.Section.allCases, id: \.self) { section in
                            let items = buckets[section] ?? []
                            if !items.isEmpty {
                                FeedSection(lane: section.lane, title: section.lane.label, count: items.count, collapsed: bindingForCollapsed(section)) {
                                    VStack(spacing: 7) {
                                        ForEach(items) { pr in
                                            PRCardView(pr: pr, lane: section.lane, hint: hint(for: pr, section: section))
                                                .onTapGesture { appState.selectedPRID = pr.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Tokens.contentBg)
        }
    }

    private func bindingForCollapsed(_ s: Section) -> Binding<Bool> {
        Binding(get: { collapsed[s] ?? false },
                set: { collapsed[s] = $0 })
    }

    private func grouped(viewerLogin: String) -> [Section: [PullRequest]] {
        var out: [Section: [PullRequest]] = [:]
        let now = Date.now
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: pr.timeline.compactMap { $0.type == .comment ? $0.actor?.login : nil },
                updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: mentionedIDs, now: now) {
                out[s, default: []].append(pr)
            }
        }
        return out
    }

    private func hint(for pr: PullRequest, section: Section) -> String? {
        switch section {
        case .attention: pr.attentionHint
        case .mentions:  pr.mentionHint
        case .involved:  pr.involvedHint
        default: nil
        }
    }
}
