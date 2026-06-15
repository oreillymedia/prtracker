import SwiftUI

struct RepoSelectorCard: View {
    let repos: [Repo]
    var onOpenSettings: () -> Void
    var onEnable: () -> Void

    @State private var showPopover = false

    private var enabledCount: Int { repos.filter(\.isEnabled).count }

    /// Single repo → its name; several → "{enabled} of {total} repos",
    /// collapsing to "{n} repos" when all are enabled.
    private var titleText: String {
        if repos.count <= 1 {
            return repos.first.map(\.name) ?? "—"
        }
        return enabledCount == repos.count ? "\(repos.count) repos" : "\(enabledCount) of \(repos.count) repos"
    }

    private var subtitleText: String {
        repos.count <= 1 ? (repos.first?.owner ?? "No repository") : "Repositories"
    }

    private var initials: String {
        repos.count <= 1 ? (repos.first?.name.prefix(2).uppercased() ?? "—") : "\(repos.count)"
    }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.79, green: 0.39, blue: 0.26),
                                     Color(red: 0.48, green: 0.18, blue: 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Text(initials).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(subtitleText).font(.system(size: 11)).foregroundStyle(Tokens.textMuted).lineLimit(1)
                    Text(titleText).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            RepoSwitcherPopover(repos: repos, onEnable: onEnable, onOpenSettings: {
                showPopover = false
                onOpenSettings()
            })
        }
    }
}
