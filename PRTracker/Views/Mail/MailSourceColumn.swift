import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        let repo = repos.first(where: \.isActive)
        VStack(spacing: 0) {
            RepoSelectorCard(repoSlug: repo?.id ?? "—", onTap: onOpenSettings)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)

            MailListView(syncActor: syncActor)

            // TODO(Task 12): replace with AccountFooter
            Divider()
            HStack { Text("Account").font(.system(size: 11)); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
