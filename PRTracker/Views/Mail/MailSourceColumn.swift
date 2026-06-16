import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    /// Leading edge of the source list's leading icon column (the 24pt TodoRing
    /// in each `MailRowView`, inset by the sidebar list's content margin). The
    /// chip badge is positioned so its center lines up with the ring center
    /// (ringColumnLeading + 12). Tune this one value to align.
    private let ringColumnLeading: CGFloat = 18

    var body: some View {
        let ringCenter = ringColumnLeading + 12   // ring is 24pt
        VStack(spacing: 0) {
            MailListView(syncActor: coordinator.syncActorForView)

            Divider()
            HStack(spacing: 8) {
                RepoSelectorCard(repos: repos, onOpenSettings: onOpenSettings,
                                 onEnable: { Task { await coordinator.refresh() } })
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.textMuted)
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            // badge center = leading + chip pad 8 + half of 20pt badge = ringCenter
            .padding(.leading, ringCenter - 18)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
        }
    }
}
