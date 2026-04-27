import SwiftUI
import SwiftData

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState
    @Query private var prs: [PullRequest]
    @Query private var repos: [Repo]
    @Query private var viewerStates: [ViewerState]

    let coordinator: SyncCoordinator
    let badge: MenuBarBadge

    var body: some View {
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)
        let buckets = grouped(viewerLogin: viewer?.login ?? "")

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repo?.id ?? "—").font(.system(size: 12).weight(.bold))
                Spacer()
                Text(coordinator.lastSyncAt.map { "Updated \(RelativeTimeFormatter.short($0))" } ?? "—")
                    .microText().foregroundStyle(Tokens.textMuted)
            }.padding(12)
            Divider()
            row(.attention, count: buckets[.attention]?.count ?? 0)
            row(.review,    count: buckets[.review]?.count ?? 0)
            row(.mine,      count: buckets[.mine]?.count ?? 0)
            row(.mentions,  count: buckets[.mentions]?.count ?? 0)
            if let top = buckets[.attention]?.first {
                Divider()
                Button {
                    appState.selectedPRID = top.id
                    openWindow(id: "main")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(top.number) \(top.title)").font(.system(size: 12).weight(.medium))
                        if let snippet = top.timeline.last(where: { $0.type == .comment })?.body {
                            Text(snippet).italic().foregroundStyle(Tokens.textMuted).lineLimit(1)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Divider()
            menuButton("Open PR Tracker", shortcut: nil) { openWindow(id: "main") }
            menuButton("Refresh now", shortcut: "⌘R") { Task { await coordinator.refresh() } }
            menuButton("Preferences…", shortcut: "⌘,") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Divider()
            menuButton("Quit", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
        }
        .frame(width: 320)
        .task(id: prs.count) {
            badge.count = (buckets[.attention] ?? []).count
        }
    }

    private func row(_ section: PRTracker.Section, count: Int) -> some View {
        Button {
            appState.activeSection = section
            openWindow(id: "main")
        } label: {
            HStack {
                Circle().fill(section.lane.color).frame(width: 8, height: 8)
                Text(section.lane.label).font(.system(size: 12))
                Spacer()
                if count > 0 { Text("\(count)").microText().foregroundStyle(Tokens.textMuted) }
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }.buttonStyle(.plain)
    }

    private func menuButton(_ label: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                if let s = shortcut { Text(s).microText().foregroundStyle(Tokens.textMuted) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }.buttonStyle(.plain)
    }

    private func grouped(viewerLogin: String) -> [PRTracker.Section: [PullRequest]] {
        var out: [PRTracker.Section: [PullRequest]] = [:]
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
                out[s, default: []].append(pr)
            }
        }
        return out
    }
}
