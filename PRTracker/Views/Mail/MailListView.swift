import SwiftUI
import SwiftData

struct MailListView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    var body: some View {
        @Bindable var appState = appState
        // Precompute the expensive per-PR todo data ONCE per render, instead of
        // rebuilding a PR's threads once per filter AND O(n log n) times inside
        // the source-list sort comparator. See todoMeta().
        let meta = todoMeta()
        let counts = filterCounts(meta: meta)
        let visible = visiblePRs(filter: appState.activeFilter, meta: meta)

        List(selection: $appState.selectedPRID) {
            if visible.isEmpty {
                Text("Nothing in this filter.")
                    .font(.system(size: 12.5).italic())
                    .foregroundStyle(Tokens.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else {
                ForEach(visible) { pr in
                    MailRowView(pr: pr, isSelected: appState.selectedPRID == pr.id, viewerLogin: viewerLogin)
                        .tag(pr.id)
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            if isResolved(pr) {
                                Button("Mark as unresolved") { markAsUnresolved(pr) }
                            } else {
                                Button("Mark as resolved") { markAsResolved(pr) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            // Clear a restored selection that no longer maps to a known PR
            // (the row was deleted between runs).
            //
            // Assumption: SwiftData's `@Query` materializes synchronously
            // against the on-disk store before this view body, so `prs` is
            // populated by the time `onAppear` fires. PRTrackerApp constructs
            // its ModelContainer eagerly, so this holds in practice.
            if let id = appState.selectedPRID, !prs.contains(where: { $0.id == id }) {
                appState.selectedPRID = nil
            }
        }
        .task(id: appState.selectedPRID) {
            // Mark the selected PR read — debounced and OFF the selection hot
            // path. Writing to the store synchronously in onChange made every
            // keypress persist to disk and re-publish the @Query (a second full
            // re-render plus "selection updated multiple times per frame"),
            // which froze keyboard navigation. .task(id:) cancels the pending
            // write whenever selection moves on, so only a settled selection saves.
            guard let id = appState.selectedPRID else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let pr = prs.first(where: { $0.id == id }) else { return }
            pr.lastReadAt = .now
            try? ctx.save()
        }
        .onChange(of: appState.activeFilter) { _, newFilter in
            let ids = visiblePRs(filter: newFilter, meta: todoMeta()).map(\.id)
            appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: ids)
        }
        .toolbar {
            ToolbarItem {
                Picker("Filter", selection: $appState.activeFilter) {
                    ForEach(MailFilter.allCases) { filter in
                        Text(label(filter, count: counts[filter] ?? 0)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Filter pull requests")
            }
        }
    }

    // MARK: - Filter predicates

    /// Precomputed per-PR todo data. Building a PR's threads from its timeline +
    /// review comments is relatively expensive; it was previously recomputed
    /// once per filter and O(n log n) times inside the source-list sort. We now
    /// compute it once per render and look it up by PR id everywhere below.
    private struct PRMeta { let ball: Bool; let counts: TodoCounts }

    private func todoMeta() -> [String: PRMeta] {
        var out: [String: PRMeta] = [:]
        out.reserveCapacity(prs.count)
        for pr in prs {
            let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
            // Mirror of TodoHelpers.ballInMyCourt, but reusing `counts` so we
            // don't build the PR's threads a second time.
            let ball: Bool
            if pr.state == .merged || pr.state == .closed {
                ball = false
            } else if counts.openMessages > 0 {
                ball = true
            } else {
                let mine = pr.author.login == viewerLogin
                ball = mine && (pr.reviewState == .changesRequested || pr.ciFail > 0)
            }
            out[pr.id] = PRMeta(ball: ball, counts: counts)
        }
        return out
    }

    private func matches(_ pr: PullRequest, filter: MailFilter, meta: [String: PRMeta]) -> Bool {
        switch filter {
        case .all:
            return true
        case .awaitingMe:
            return meta[pr.id]?.ball ?? false
        case .open:
            // GitHub-style "open": PR is not merged/closed. Source-list rows
            // don't have full thread data (timeline + reviewComments are
            // lazy-fetched on detail open), so the stricter "has unresolved
            // threads" check would falsely exclude most PRs.
            return pr.state == .open || pr.state == .draft
        case .mine:
            return pr.author.login == viewerLogin && pr.state == .open
        case .done:
            let counts = meta[pr.id]?.counts
            return pr.state == .open && (counts?.total ?? 0) > 0 && (counts?.open ?? 0) == 0
        case .recent:
            return pr.state == .merged
        }
    }

    private func visiblePRs(filter: MailFilter, meta: [String: PRMeta]) -> [PullRequest] {
        prs.filter { matches($0, filter: filter, meta: meta) }
           .sorted { a, b in
               let aw = (meta[a.id]?.ball ?? false) ? 0 : 1
               let bw = (meta[b.id]?.ball ?? false) ? 0 : 1
               if aw != bw { return aw < bw }
               return a.updatedAt > b.updatedAt
           }
    }

    private func filterCounts(meta: [String: PRMeta]) -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        for filter in MailFilter.allCases {
            c[filter] = prs.filter { matches($0, filter: filter, meta: meta) }.count
        }
        return c
    }

    private func label(_ filter: MailFilter, count: Int) -> String {
        count > 0 ? "\(filter.label) (\(count))" : filter.label
    }

    // MARK: - Actions

    private func isResolved(_ pr: PullRequest) -> Bool {
        guard pr.state == .open else { return false }
        let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        guard counts.total > 0, counts.open == 0 else { return false }
        if pr.author.login == viewerLogin && pr.ciFail > 0 { return false }
        return true
    }

    private func markAsResolved(_ pr: PullRequest) {
        for e in pr.timeline where e.type == .comment || (e.type == .review && !(e.body ?? "").isEmpty) {
            if e.actor?.login != viewerLogin { e.isDone = true }
        }
        for c in pr.reviewComments where c.author.login != viewerLogin {
            c.isDone = true
        }
        try? ctx.save()
    }

    private func markAsUnresolved(_ pr: PullRequest) {
        for e in pr.timeline where e.type == .comment || (e.type == .review && !(e.body ?? "").isEmpty) {
            if e.actor?.login != viewerLogin { e.isDone = false }
        }
        for c in pr.reviewComments where c.author.login != viewerLogin {
            c.isDone = false
        }
        try? ctx.save()
    }

}
