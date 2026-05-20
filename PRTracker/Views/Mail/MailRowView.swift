import SwiftUI

struct MailRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let onToggleRead: () -> Void

    @State private var hover = false

    private var bucket: Section? {
        // Best-effort lane derivation for the priority rail. The hint fields
        // (set by sync) carry the most specific bucket; if none is set we fall
        // back to merged-vs-open. Authoritative classification (which requires
        // the viewer login) happens in MailListView (Task 10) — the rail color
        // here is decorative.
        if pr.attentionHint != nil { return .attention }
        if pr.mentionHint   != nil { return .mentions }
        if pr.involvedHint  != nil { return .involved }
        switch pr.state {
        case .merged: return .recent
        case .open:   return .mine
        default:      return nil
        }
    }

    private var laneColor: Color { (bucket?.lane.color) ?? Tokens.textFaint }

    var body: some View {
        ZStack(alignment: .leading) {
            // Priority rail
            RoundedRectangle(cornerRadius: 2)
                .fill(laneColor)
                .frame(width: 3)
                .padding(.vertical, 6)
                .opacity(pr.isUnread ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 4) {
                topLine
                bottomLine
                if let hint = preview {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.leading, 15)
                        .padding(.top, 1)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)
        .opacity(pr.isUnread || isSelected ? 1 : 0.62)
        .onHover { hover = $0 }
        .contextMenu {
            Button(pr.isUnread ? "Mark as read" : "Mark as unread", action: onToggleRead)
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: pr.isUnread)
    }

    private var rowBackground: Color {
        if isSelected { return Tokens.rowSelect }
        if hover { return Tokens.rowHover }
        return .clear
    }

    private var topLine: some View {
        HStack(alignment: .center, spacing: 7) {
            UnreadDot(on: pr.isUnread)
            Text(pr.title)
                .font(.system(size: 13, weight: pr.isUnread ? .bold : .medium))
                .foregroundStyle(isSelected ? Tokens.accentText : Tokens.text)
                .tracking(-0.05)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RelativeTimeFormatter.short(pr.updatedAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
                .lineLimit(1)
        }
    }

    private var bottomLine: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 16)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
                .lineLimit(1)
            Text("·")
                .foregroundStyle(Tokens.textFaint)
            Text("#\(pr.number)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
            Spacer(minLength: 0)
            if pr.state == .merged {
                mergedPill
            } else {
                MiniGaugeDots(pr: pr)
            }
        }
    }

    private var mergedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 10).weight(.semibold))
            Text("Merged").font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Lane.recent.color)
    }

    private var preview: String? {
        pr.attentionHint ?? pr.mentionHint ?? pr.involvedHint
    }
}
