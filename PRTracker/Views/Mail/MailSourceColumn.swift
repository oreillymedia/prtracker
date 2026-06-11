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
            MailListView(syncActor: syncActor)

            Divider()
            RepoSelectorCard(repoSlug: repo?.id ?? "—", onTap: onOpenSettings)
                .padding(.horizontal, 12).padding(.vertical, 8)
            AccountFooter(viewer: viewer, onOpenSettings: onOpenSettings)
        }
    }
}
