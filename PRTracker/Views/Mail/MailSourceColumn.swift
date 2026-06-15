import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]
    @Query private var viewerStates: [ViewerState]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        let viewer = viewerStates.first?.viewer
        VStack(spacing: 0) {
            MailListView(syncActor: coordinator.syncActorForView)

            Divider()
            RepoSelectorCard(repos: repos, onOpenSettings: onOpenSettings,
                             onEnable: { Task { await coordinator.refresh() } })
                .padding(.horizontal, 12).padding(.vertical, 8)
            AccountFooter(viewer: viewer, onOpenSettings: onOpenSettings)
        }
    }
}
