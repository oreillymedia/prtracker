import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // TODO(Task 11): replace with RepoSelectorCard
            Text("Repo Selector").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)

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
