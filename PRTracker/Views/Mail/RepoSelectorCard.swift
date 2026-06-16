import SwiftUI

/// Compact "N Repositories" chip at the bottom of the sidebar. Tapping opens the
/// repo switcher popover.
struct RepoSelectorCard: View {
    let repos: [Repo]
    var onOpenSettings: () -> Void
    var onEnable: () -> Void

    @State private var showPopover = false

    private var activeCount: Int { repos.filter(\.isEnabled).count }

    var body: some View {
        HStack {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 8) {
                    Text("\(activeCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Tokens.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 5))
                    Text(activeCount == 1 ? "Active Repository" : "Active Repositories")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tokens.textFaint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
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
            Spacer(minLength: 0)
        }
    }
}
