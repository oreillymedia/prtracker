import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        let repo = repos.first(where: \.isActive)
        let viewer = viewerStates.first?.viewer
        VStack(spacing: 0) {
            RepoSelectorCard(repoSlug: repo?.id ?? "—", onTap: onOpenSettings)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)

            MailListView(syncActor: syncActor)

            AccountFooter(viewer: viewer, onOpenSettings: onOpenSettings)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
