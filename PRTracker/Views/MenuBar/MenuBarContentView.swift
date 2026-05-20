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
        let sectionOrder: [PRTracker.Section] = [.attention, .review, .mine, .mentions, .involved, .recent]

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repo?.id ?? "—").font(.system(size: 12).weight(.bold))
                Spacer()
                Text(coordinator.lastSyncAt.map { "Updated \(RelativeTimeFormatter.short($0))" } ?? "—")
                    .microText().foregroundStyle(Tokens.textMuted)
            }.padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sectionOrder, id: \.self) { section in
                        if let sectionPRs = buckets[section], !sectionPRs.isEmpty {
                            sectionHeader(section)
                            ForEach(sectionPRs, id: \.id) { pr in
                                prRow(pr)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)

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

    // MARK: - Compressed PR row

    private func prRow(_ pr: PullRequest) -> some View {
        Button {
            appState.selectedPRID = pr.id
            openWindow(id: "main")
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(laneColor(for: pr))
                    .frame(width: 3)
                    .opacity(pr.isUnread ? 1 : 0.5)

                HStack(spacing: 7) {
                    UnreadDot(on: pr.isUnread)
                    Text(pr.title)
                        .font(.system(size: 12, weight: pr.isUnread ? .bold : .medium))
                        .foregroundStyle(Tokens.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(RelativeTimeFormatter.short(pr.updatedAt))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Tokens.textFaint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .opacity(pr.isUnread ? 1 : 0.62)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ section: PRTracker.Section) -> some View {
        Text(section.lane.label)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Tokens.textFaint)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: - Lane color helper

    private func laneColor(for pr: PullRequest) -> Color {
        if pr.attentionHint != nil { return Lane.attention.color }
        if pr.mentionHint   != nil { return Lane.mentions.color }
        if pr.involvedHint  != nil { return Lane.involved.color }
        switch pr.state {
        case .merged: return Lane.recent.color
        case .open:   return Lane.mine.color
        default:      return Tokens.textFaint
        }
    }

    // MARK: - Menu button

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

    // MARK: - Grouping

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
