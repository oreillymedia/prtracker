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
            syncStatusRow
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

    /// Sync feedback for the main window: a spinner while a background sync runs,
    /// otherwise the time of the last successful sync. (`SyncCoordinator` is
    /// `@Observable`, so reading these here keeps the row live.)
    @ViewBuilder
    private var syncStatusRow: some View {
        HStack(spacing: 6) {
            if coordinator.isSyncing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Updating…").microText().foregroundStyle(Tokens.textMuted)
            } else if let err = coordinator.lastSyncError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9)).foregroundStyle(Tokens.changes)
                Text(syncErrorText(err)).microText().foregroundStyle(Tokens.changes)
            } else if let last = coordinator.lastSyncAt {
                Text("Updated \(RelativeTimeFormatter.short(last))").microText().foregroundStyle(Tokens.textMuted)
            } else {
                Text("Not yet synced").microText().foregroundStyle(Tokens.textFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func syncErrorText(_ err: GitHubError) -> String {
        switch err {
        case .unauthorized:   return "Sync failed — check your token"
        case .repoNotFound:   return "Sync failed — repo not found"
        case .rateLimited:    return "Sync paused — rate limited"
        case .network:        return "Sync failed — network error"
        case .decoding:       return "Sync failed — unexpected response"
        case .notModified:    return "Up to date"
        }
    }
}
