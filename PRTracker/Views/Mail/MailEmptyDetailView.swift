import SwiftUI
import SwiftData

/// Shown in the detail pane when no pull request is selected. Beyond the prompt
/// to pick one, it surfaces a small at-a-glance summary of the current queue so
/// the empty state still tells you whether anything needs attention.
struct MailEmptyDetailView: View {
    @Query private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }
    private var activeRepoName: String? { repos.first(where: \.isActive)?.name }

    private struct Summary { var awaitingMe = 0; var open = 0; var merged = 0 }

    /// Mirrors the counting in `MailListView` (`awaitingMe` = ball-in-court,
    /// `open` = open/draft, `merged` = merged). Only runs while the detail pane
    /// is empty, so the per-PR `rowMeta` build is off the selection hot path.
    private var summary: Summary {
        var s = Summary()
        for pr in prs {
            if pr.state == .open || pr.state == .draft { s.open += 1 }
            if pr.state == .merged { s.merged += 1 }
            if TodoHelpers.rowMeta(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt).ball { s.awaitingMe += 1 }
        }
        return s
    }

    var body: some View {
        let s = summary
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Tokens.accent.opacity(0.12))
                        .frame(width: 76, height: 76)
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Tokens.accent)
                }
                VStack(spacing: 5) {
                    Text("No Pull Request Selected")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Tokens.text)
                    Text(activeRepoName.map { "Select a pull request from \($0) to see its details." }
                         ?? "Select a pull request from the sidebar to see its details.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textMuted)
                        .multilineTextAlignment(.center)
                }
            }

            if !prs.isEmpty {
                HStack(spacing: 12) {
                    stat("Awaiting you", count: s.awaitingMe, color: Lane.attention.color)
                    stat("Open", count: s.open, color: Lane.review.color)
                    stat("Merged", count: s.merged, color: Lane.recent.color)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func stat(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
        }
        .frame(minWidth: 92)
        .padding(.vertical, 14)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.border, lineWidth: 0.5))
    }
}
