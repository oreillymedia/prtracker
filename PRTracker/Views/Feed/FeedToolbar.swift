import SwiftUI

struct FeedToolbar: View {
    let repoSlug: String
    let lastSyncAt: Date?
    let isSyncing: Bool
    let lastError: GitHubError?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PR Tracker").font(.system(size: 14).weight(.semibold))
                Text(repoSlug).font(.system(size: 11.5)).foregroundStyle(Tokens.textMuted)
            }
            Spacer()
            statusChip
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(isSyncing)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder private var statusChip: some View {
        if isSyncing {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Refreshing…").microText() }
        } else if let lastError {
            Text(errorMessage(lastError)).microText().foregroundStyle(Tokens.changes)
        } else if let t = lastSyncAt {
            HStack(spacing: 6) { Image(systemName: "clock"); Text("Updated \(RelativeTimeFormatter.short(t))").microText() }
                .foregroundStyle(Tokens.textMuted)
        } else {
            EmptyView()
        }
    }

    private func errorMessage(_ e: GitHubError) -> String {
        switch e {
        case .unauthorized: "Token rejected"
        case .repoNotFound: "Repo not found"
        case .rateLimited: "Rate-limited"
        case .network: "Sync failed — click refresh"
        case .decoding: "Schema error"
        case .notModified: "Up to date"
        }
    }
}
