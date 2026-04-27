import SwiftUI
import SwiftData

struct PRDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    let pr: PullRequest
    let viewer: User?
    let client: GitHubClient
    let syncActor: SyncActor

    @State private var loadError: GitHubError?

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let loadError {
                            Text("Couldn't load timeline: \(String(describing: loadError)). Click refresh to retry.")
                                .foregroundStyle(Tokens.changes).padding(8)
                                .background(Tokens.changes.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        TimelineColumn(events: pr.timeline,
                            onTapEvent: { e in Task { try? await syncActor.setSeen(eventID: e.id, isSeen: !e.isSeen) } },
                            onMarkUpToHere: { e in Task { try? await syncActor.setSeenUpTo(prID: pr.id, throughEventID: e.id) } })
                        QuickReply(viewer: viewer)
                    }.padding(20)
                }
                DetailRightRail(pr: pr,
                    onMarkAllSeen: { Task { try? await syncActor.setSeenForPR(prID: pr.id, isSeen: true) } },
                    onMarkAllUnseen: { Task { try? await syncActor.setSeenForPR(prID: pr.id, isSeen: false) } })
            }
        }
        .task(id: pr.id) { await loadTimeline() }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { appState.selectedPRID = nil } label: {
                    SwiftUI.Label("Feed", systemImage: "chevron.left")
                }.buttonStyle(.borderless)
                Text("\(pr.repo.id) / #\(pr.number)").foregroundStyle(Tokens.textMuted)
                Spacer()
                Link("Open", destination: URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)")!)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Tokens.accentBg, in: Capsule())
            }
            Text(pr.title).font(.system(size: 18).weight(.bold)).tracking(-0.2)
            HStack(spacing: 6) {
                AvatarView(user: pr.author, size: 18)
                Text(pr.author.name ?? pr.author.login).metaText()
                Text("wants to merge into").foregroundStyle(Tokens.textFaint)
                Text(pr.branchBase).monoText().padding(.horizontal, 4).background(Tokens.hairline, in: Capsule())
                Text("from").foregroundStyle(Tokens.textFaint)
                Text(pr.branchHead).monoText().padding(.horizontal, 4).background(Tokens.hairline, in: Capsule())
                Text("· opened \(RelativeTimeFormatter.short(pr.openedAt))").foregroundStyle(Tokens.textFaint).microText()
            }
        }
        .padding(24)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    private func loadTimeline() async {
        let ref = RepoRef(owner: pr.repo.owner, name: pr.repo.name)
        let number = pr.number
        let prID = pr.id
        do {
            async let t = client.timeline(repo: ref, number: number)
            async let r = client.reviews(repo: ref, number: number)
            async let c = client.issueComments(repo: ref, number: number)
            let (tItems, _, _) = try await (t, r, c)
            try await syncActor.upsertTimeline(prID: prID, items: tItems)
            loadError = nil
        } catch let e as GitHubError {
            loadError = e
        } catch {
            loadError = .network(message: error.localizedDescription)
        }
    }
}
