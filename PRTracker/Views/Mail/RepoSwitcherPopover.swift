import SwiftUI
import SwiftData

/// Compact on/off control for the configured repos, shown from the sidebar repo
/// card. Toggling writes the same `isEnabled` flag as the Settings → Repos tab —
/// turning a repo off hides its PRs and stops its notifications without losing
/// any stored data. Enabling triggers a sync so its PRs appear promptly.
struct RepoSwitcherPopover: View {
    @Environment(\.modelContext) private var ctx

    let repos: [Repo]
    var onEnable: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(repos) { repo in
                Toggle(isOn: Binding(
                    get: { repo.isEnabled },
                    set: { newValue in
                        repo.isEnabled = newValue
                        try? ctx.save()
                        if newValue { onEnable() }
                    })) {
                    Text(repo.id).font(.system(size: 12)).lineLimit(1)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }

            if repos.isEmpty {
                Text("No repositories yet.")
                    .microText().foregroundStyle(Tokens.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }

            Divider()
            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    Text("Manage repos…").font(.system(size: 12))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 240)
        .padding(.vertical, 6)
    }
}
