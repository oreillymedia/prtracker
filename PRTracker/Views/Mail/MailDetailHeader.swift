import SwiftUI

struct MailDetailHeader: View {
    let pr: PullRequest
    let todoCounts: TodoCounts
    let ciFailedForMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow
            if todoCounts.total > 0 || ciFailedForMe {
                TodoSummaryBar(counts: todoCounts, ciFailedForMe: ciFailedForMe)
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
        }
    }
}
