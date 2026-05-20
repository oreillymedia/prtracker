import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            // TODO(Task 11): replace with RepoSelectorCard
            Text("Repo Selector").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)

            // TODO(Task 10): replace with MailListView (filter pills + rows)
            List(selection: $appState.selectedPRID) {
                ForEach(prs) { pr in
                    MailRowView(
                        pr: pr,
                        isSelected: appState.selectedPRID == pr.id,
                        onToggleRead: { toggleRead(pr) }
                    )
                    .tag(pr.id)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // TODO(Task 12): replace with AccountFooter
            Divider()
            HStack { Text("Account").font(.system(size: 11)); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }

    private func toggleRead(_ pr: PullRequest) {
        let id = pr.id
        let wasUnread = pr.isUnread
        Task {
            try? await syncActor.setLastReadAt(prID: id, date: wasUnread ? .now : nil)
        }
    }
}
