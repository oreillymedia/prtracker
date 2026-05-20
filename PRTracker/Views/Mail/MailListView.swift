import SwiftUI
import SwiftData

struct MailListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor

    var body: some View {
        @Bindable var appState = appState
        let viewerLogin = viewerStates.first?.viewer?.login ?? ""
        let buckets = grouped(viewerLogin: viewerLogin)
        let counts = counts(from: buckets)
        let visible = visiblePRs(buckets: buckets, filter: appState.activeFilter)

        VStack(spacing: 0) {
            FilterPillBar(active: $appState.activeFilter, counts: counts)
            List(selection: $appState.selectedPRID) {
                if visible.isEmpty {
                    Text("Nothing in this filter.")
                        .font(.system(size: 12.5).italic())
                        .foregroundStyle(Tokens.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visible) { pr in
                        MailRowView(
                            pr: pr,
                            isSelected: appState.selectedPRID == pr.id,
                            onToggleRead: { toggleRead(pr) }
                        )
                        .tag(pr.id)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: appState.activeFilter) { _, newFilter in
            let freshBuckets = grouped(viewerLogin: viewerStates.first?.viewer?.login ?? "")
            reconcileSelection(visiblePRs: visiblePRs(buckets: freshBuckets, filter: newFilter))
        }
    }

    private func grouped(viewerLogin: String) -> [Section: [PullRequest]] {
        var out: [Section: [PullRequest]] = [:]
        let now = Date.now
        let mentionedIDs = Set(prs.compactMap { $0.mentionHint != nil ? $0.id : nil })
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

    private func counts(from buckets: [Section: [PullRequest]]) -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        var total = 0
        for filter in MailFilter.allCases where filter != .all {
            if let s = filter.section {
                let n = buckets[s]?.count ?? 0
                c[filter] = n
                total += n
            }
        }
        c[.all] = total
        return c
    }

    private func visiblePRs(buckets: [Section: [PullRequest]], filter: MailFilter) -> [PullRequest] {
        if let s = filter.section { return buckets[s] ?? [] }
        var seen = Set<String>(); var out: [PullRequest] = []
        for s in Section.allCases {
            for pr in buckets[s] ?? [] where !seen.contains(pr.id) {
                seen.insert(pr.id); out.append(pr)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func reconcileSelection(visiblePRs: [PullRequest]) {
        let ids = visiblePRs.map(\.id)
        appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: ids)
    }

    private func toggleRead(_ pr: PullRequest) {
        let id = pr.id
        let wasUnread = pr.isUnread
        Task {
            try? await syncActor.setLastReadAt(prID: id, date: wasUnread ? .now : nil)
        }
    }
}
