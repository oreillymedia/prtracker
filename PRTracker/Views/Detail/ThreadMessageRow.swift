import SwiftUI

struct ThreadMessageRow: View {
    let message: ThreadMessage
    let onToggleDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingRail
            AvatarView(user: message.actor, size: 22)
            VStack(alignment: .leading, spacing: 4) {
                headerLine
                MarkdownText(raw: message.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Tokens.accent).frame(width: 3)
                .opacity((message.isNew && !message.isDone) ? 1 : 0)
        }
        .opacity((message.isDone && !message.isMine) ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var leadingRail: some View {
        if message.isMine {
            Text("↳")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Tokens.textFaint)
                .frame(width: 18)
        } else {
            TodoCheckbox(isOn: message.isDone, onTap: onToggleDone)
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(message.actor.name ?? message.actor.login)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.text)
                .strikethrough(message.isDone && !message.isMine, color: Tokens.textFaint)
            if message.isMine { youTag }
            if message.isNew && !message.isDone { newTag }
            Spacer(minLength: 0)
            Text(RelativeTimeFormatter.short(message.createdAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
        }
    }

    private var youTag: some View {
        Text("YOU")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(Tokens.textMuted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 3))
    }

    private var newTag: some View {
        Text("NEW")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Tokens.accent)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Tokens.accentBg, in: RoundedRectangle(cornerRadius: 3))
    }

    private var rowBackground: Color {
        (message.isNew && !message.isDone) ? Tokens.newHighlight : .clear
    }
}
