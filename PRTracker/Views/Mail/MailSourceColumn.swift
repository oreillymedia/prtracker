import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]

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
                    Text("#\(pr.number) — \(pr.title)").lineLimit(1).tag(pr.id)
                }
            }
            .listStyle(.plain)

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
