import SwiftUI
import SwiftData

/// Repo switcher shown from the sidebar's "N Repositories" chip. Lists every
/// configured repo with an avatar, open-PR count, and an on/off switch (the same
/// `isEnabled` flag as Settings — turning a repo off hides its PRs and stops its
/// notifications without losing data). Enabling triggers a sync. A footer link
/// opens the full Repositories settings.
struct RepoSwitcherPopover: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage(SettingsTab.storageKey) private var selectedSettingsTab: SettingsTab = .general

    let repos: [Repo]
    var onEnable: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRACKED REPOSITORIES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Tokens.textFaint)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            if repos.isEmpty {
                Text("No repositories yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textMuted)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            } else {
                ForEach(repos) { repo in
                    repoRow(repo)
                }
            }

            Divider().padding(.vertical, 4)

            Button(action: { selectedSettingsTab = .repositories; onOpenSettings() }) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(Tokens.textMuted)
                    Text("Manage repositories…").font(.system(size: 13)).foregroundStyle(Tokens.text)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 330)
        .padding(.bottom, 6)
    }

    private func repoRow(_ repo: Repo) -> some View {
        HStack(spacing: 11) {
            Text(initial(repo))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(repo.isEnabled ? .white : Tokens.textMuted)
                .frame(width: 34, height: 34)
                .background(repo.isEnabled ? Tokens.accent : Tokens.hairline,
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.id)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.text).lineLimit(1)
                Text(notificationText(repo))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { repo.isEnabled },
                set: { newValue in
                    repo.isEnabled = newValue
                    try? ctx.save()
                    if newValue { onEnable() }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private func initial(_ repo: Repo) -> String {
        repo.name.first.map { String($0).uppercased() } ?? "?"
    }

    /// The repo's notification strategy, shown as the row's subtitle.
    private func notificationText(_ repo: Repo) -> String {
        switch repo.notificationLevel {
        case .everything: return "Everything"
        case .personal:   return "Personal"
        case .none:       return "Notifications off"
        }
    }
}
