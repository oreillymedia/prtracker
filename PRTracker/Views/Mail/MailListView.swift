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
        let counts = pillCounts()
        let visible = visiblePRs(filter: appState.activeFilter)

        VStack(spacing: 0) {
            FilterPillBar(active: $appState.activeFilter, counts: counts)
            ScrollView {
                if visible.isEmpty {
                    Text("Nothing in this filter.")
                        .font(.system(size: 12.5).italic())
                        .foregroundStyle(Tokens.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { pr in
                            Button {
                                appState.selectedPRID = pr.id
                            } label: {
                                MailRowView(pr: pr,
                                            isSelected: appState.selectedPRID == pr.id,
                                            viewerLogin: viewerLogin)
                                    .background(appState.selectedPRID == pr.id ? Tokens.rowSelect : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow)   { moveSelection(by: -1, in: visible); return .handled }
            .onKeyPress(.downArrow) { moveSelection(by:  1, in: visible); return .handled }
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
        case .mentions:
            return pr.mentionHint != nil
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

    private func pillCounts() -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        for filter in MailFilter.allCases {
            c[filter] = prs.filter { matches($0, filter: filter) }.count
        }
        return c
    }

    // MARK: - Keyboard navigation

    private func moveSelection(by delta: Int, in visible: [PullRequest]) {
        guard !visible.isEmpty else { return }
        let ids = visible.map(\.id)
        guard let current = appState.selectedPRID,
              let idx = ids.firstIndex(of: current) else {
            appState.selectedPRID = delta > 0 ? ids.first : ids.last
            return
        }
        let next = max(0, min(ids.count - 1, idx + delta))
        appState.selectedPRID = ids[next]
    }
}
