import SwiftUI

struct ReviewCommentCard: View {
    let comment: ReviewComment
    let showsAnchor: Bool   // false for replies; they inherit the root's path:line + diff_hunk
    var onToggleSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsAnchor {
                breadcrumb
                diffHunkBlock
            }
            authorRow
            MarkdownText(raw: comment.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
        .opacity(comment.isSeen ? 0.48 : 1)
        .contextMenu {
            Button(comment.isSeen ? "Mark unseen" : "Mark seen", action: onToggleSeen)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 0) {
            Text(comment.path).font(.system(size: 10.5).monospaced())
            if let line = comment.line {
                Text(":\(line)").font(.system(size: 10.5).monospaced())
            }
        }
        .foregroundStyle(Tokens.textFaint)
    }

    private var diffHunkBlock: some View {
        Text(comment.diffHunk)
            .font(.system(size: 11).monospaced())
            .foregroundStyle(Tokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            AvatarView(user: comment.author, size: 18)
            Text(comment.author.name ?? comment.author.login)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.text)
            Spacer()
            RelativeTimeText(date: comment.createdAt)
                .font(.system(size: 10.5))
                .foregroundStyle(Tokens.textFaint)
        }
    }
}
