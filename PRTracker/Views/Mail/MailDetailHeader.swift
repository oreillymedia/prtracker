import SwiftUI

struct MailDetailHeader: View {
    let pr: PullRequest
    let isRefreshing: Bool
    let lastUpdatedAt: Date?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbarRow
            Text(pr.title)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.2)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            metadataRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Text(pr.repo.name).font(.system(size: 11.5)).foregroundStyle(Tokens.textFaint)
            Text("/").foregroundStyle(Tokens.textFaint)
            Text("#\(pr.number)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Tokens.textMuted)
            Text("·").foregroundStyle(Tokens.textFaint)
            statePill
            Spacer()
            updatedChip
            openOnGitHubLink
            refreshButton
        }
    }

    @ViewBuilder private var statePill: some View {
        let color = stateColor
        HStack(spacing: 4) {
            Image(systemName: stateIcon).font(.system(size: 11, weight: .semibold))
            Text(stateLabel).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 1)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    @ViewBuilder private var updatedChip: some View {
        if isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Refreshing…").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            }
        } else if let t = lastUpdatedAt {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 11))
                Text("Updated \(RelativeTimeFormatter.short(t))").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            }
        }
    }

    private var openOnGitHubLink: some View {
        Link(destination: URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)")!) {
            HStack(spacing: 4) {
                Text("Open on GitHub").font(.system(size: 12, weight: .medium)).foregroundStyle(Tokens.text)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.textMuted)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.textMuted)
                .frame(width: 24, height: 24)
                .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help("Refresh")
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 18)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.text)
            Text("wants to merge into").foregroundStyle(Tokens.textMuted).font(.system(size: 11.5))
            Text(pr.branchBase)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
            Text("from").foregroundStyle(Tokens.textMuted).font(.system(size: 11.5))
            Text(pr.branchHead)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
            Text("·").foregroundStyle(Tokens.textFaint)
            Text("opened \(RelativeTimeFormatter.short(pr.openedAt))")
                .foregroundStyle(Tokens.textFaint).font(.system(size: 11))
        }
    }

    private var stateLabel: String {
        switch pr.state { case .open: "Open"; case .merged: "Merged"; case .closed: "Closed"; case .draft: "Draft" }
    }
    private var stateIcon: String {
        switch pr.state {
        case .open:   "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .draft:  "circle.dashed"
        }
    }
    private var stateColor: Color {
        switch pr.state {
        case .open:   Tokens.approved
        case .merged: Lane.recent.color
        case .closed: Tokens.changes
        case .draft:  Tokens.textMuted
        }
    }
}
