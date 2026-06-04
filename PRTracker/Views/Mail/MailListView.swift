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
        let counts = filterCounts()
        let visible = visiblePRs(filter: appState.activeFilter)

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
        .onChange(of: appState.selectedPRID) { _, newID in
            // Update lastReadAt on the newly selected PR (semantically: lastSeenAt).
            guard let newID, let pr = prs.first(where: { $0.id == newID }) else { return }
            pr.lastReadAt = .now
            try? ctx.save()
        }
        .onChange(of: appState.activeFilter) { _, newFilter in
            let ids = visiblePRs(filter: newFilter).map(\.id)
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

    private func matches(_ pr: PullRequest, filter: MailFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .awaitingMe:
            return TodoHelpers.ballInMyCourt(pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        case .open:
            // GitHub-style "open": PR is not merged/closed. Source-list rows
            // don't have full thread data (timeline + reviewComments are
            // lazy-fetched on detail open), so the stricter "has unresolved
            // threads" check would falsely exclude most PRs.
            return pr.state == .open || pr.state == .draft
        case .mine:
            return pr.author.login == viewerLogin && pr.state == .open
        case .done:
            let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
            return pr.state == .open && counts.total > 0 && counts.open == 0
        case .recent:
            return pr.state == .merged
        }
    }

    private func visiblePRs(filter: MailFilter) -> [PullRequest] {
        prs.filter { matches($0, filter: filter) }
           .sorted(by: ballInMyCourtFirst)
    }

    private func ballInMyCourtFirst(_ a: PullRequest, _ b: PullRequest) -> Bool {
        let aw = TodoHelpers.ballInMyCourt(a, viewerLogin: viewerLogin, lastSeenAt: a.lastSeenAt) ? 0 : 1
        let bw = TodoHelpers.ballInMyCourt(b, viewerLogin: viewerLogin, lastSeenAt: b.lastSeenAt) ? 0 : 1
        if aw != bw { return aw < bw }
        return a.updatedAt > b.updatedAt
    }

    private func filterCounts() -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        for filter in MailFilter.allCases {
            c[filter] = prs.filter { matches($0, filter: filter) }.count
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
