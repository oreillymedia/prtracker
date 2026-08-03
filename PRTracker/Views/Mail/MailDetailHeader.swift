import SwiftUI

struct MailDetailHeader: View {
    let pr: PullRequest
    let todoCounts: TodoCounts
    let ciFailedForMe: Bool
    var isUpdating: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow
            if todoCounts.total > 0 || ciFailedForMe {
                TodoSummaryBar(counts: todoCounts, ciFailedForMe: ciFailedForMe, isUpdating: isUpdating)
                    .padding(.top, 2)
            } else if isUpdating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Updating…").font(.system(size: 11.5)).foregroundStyle(Tokens.textMuted)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Divider(), alignment: .bottom)
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let state = PRStatePill.Kind(pr.state) {
                PRStatePill(kind: state)
            }
            AvatarView(user: pr.author, size: 18)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.text)
            Text(pr.branchHead)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
            Text(Image(systemName: "arrow.forward"))
                .foregroundStyle(Tokens.textMuted)
                .font(.system(size: 11.5))
            Text(pr.branchBase)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
