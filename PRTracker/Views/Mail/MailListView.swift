import SwiftUI
import SwiftData

struct MailListView: View {
    @Environment(AppState.self) private var appState
    // Enabled-repo PRs only, filtered at the fetch. Excludes disabled and
    // cascade-deleted repos' PRs without dereferencing `repo` in the body.
    @Query(filter: #Predicate<PullRequest> { $0.repo.isEnabled },
           sort: [SortDescriptor(\PullRequest.lastActivityAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    var body: some View {
        @Bindable var appState = appState
        // Precompute the expensive per-PR thread data ONCE per render. This body
        // intentionally does NOT read `selectedPRID` — only `prs` and
        // `activeFilter` — so changing selection re-renders `SourceList` (cheap)
        // without rebuilding `meta` for every PR. See rowMetaByID() / SourceList.
        // `prs` is already scoped to enabled repos by the @Query predicate, so
        // disabled / cascade-deleted repos' PRs never reach the body.
        let meta = rowMetaByID(prs)
        let counts = filterCounts(prs, meta: meta)
        let visible = visiblePRs(prs, filter: appState.activeFilter, meta: meta)

        SourceList(prs: prs, visible: visible, meta: meta, viewerLogin: viewerLogin)
            .onChange(of: appState.activeFilter) { _, newFilter in
                let ids = visiblePRs(prs, filter: newFilter, meta: meta).map(\.id)
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

    /// Precomputed per-PR thread data. Building a PR's threads from its timeline +
    /// review comments is relatively expensive; we compute it once per render and
    /// look it up by PR id for filtering, sorting, counts, AND row rendering.
    private func rowMetaByID(_ prs: [PullRequest]) -> [String: PRRowMeta] {
        var out: [String: PRRowMeta] = [:]
        out.reserveCapacity(prs.count)
        for pr in prs {
            out[pr.id] = TodoHelpers.rowMeta(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        }
        return out
    }

    private func matches(_ pr: PullRequest, filter: MailFilter, meta: [String: PRRowMeta]) -> Bool {
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

    private func visiblePRs(_ prs: [PullRequest], filter: MailFilter, meta: [String: PRRowMeta]) -> [PullRequest] {
        prs.filter { matches($0, filter: filter, meta: meta) }
           .sorted { a, b in
               let aw = (meta[a.id]?.ball ?? false) ? 0 : 1
               let bw = (meta[b.id]?.ball ?? false) ? 0 : 1
               if aw != bw { return aw < bw }
               return a.lastActivityAt > b.lastActivityAt
           }
    }

    private func filterCounts(_ prs: [PullRequest], meta: [String: PRRowMeta]) -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        for filter in MailFilter.allCases {
            c[filter] = prs.filter { matches($0, filter: filter, meta: meta) }.count
        }
        return c
    }

    private func label(_ filter: MailFilter, count: Int) -> String {
        count > 0 ? "\(filter.label) (\(count))" : filter.label
    }
}

// MARK: - Source list

/// The selection-bound list. Isolated from `MailListView` so that changing the
/// selection only re-renders this view (with the already-built `meta`/`visible`),
/// instead of re-running the parent body and rebuilding per-PR thread data.
private struct SourceList: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var ctx

    let prs: [PullRequest]
    let visible: [PullRequest]
    let meta: [String: PRRowMeta]
    let viewerLogin: String

    /// `visible` (filter-matched + sorted) narrowed by the live title search.
    /// Applying search here — in the isolated child — keeps it off the parent's
    /// `meta`-rebuild path, so typing doesn't recompute per-PR thread data.
    private var shown: [PullRequest] {
        let q = appState.searchText
        guard !q.isEmpty else { return visible }
        return visible.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedPRID) {
            if shown.isEmpty {
                Text(appState.searchText.isEmpty ? "Nothing in this filter." : "No matches.")
                    .font(.system(size: 12.5).italic())
                    .foregroundStyle(Tokens.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else {
                ForEach(shown) { pr in
                    MailRowView(pr: pr, meta: meta[pr.id], isSelected: appState.selectedPRID == pr.id, viewerLogin: viewerLogin)
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
        .searchable(text: $appState.searchText, placement: .sidebar, prompt: "Search titles")
        .onChange(of: appState.searchText) { _, _ in
            // Keep selection valid when search hides the selected row.
            appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: shown.map(\.id))
        }
        .onChange(of: shown.map(\.id)) { _, ids in
            // Keep selection valid when the visible set itself changes — e.g. a
            // repo is disabled/deleted and its rows drop out. Without this the
            // List(selection:) holds a PR id no longer present.
            appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: ids)
        }
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
