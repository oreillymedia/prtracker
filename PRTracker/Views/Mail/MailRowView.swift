import SwiftUI

struct MailRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let viewerLogin: String

    /// `.increased` when this row is the selected row of a focused list — i.e.
    /// when the native accent selection capsule is drawn behind it. We flip the
    /// row's content to white in that state so it reads on the accent (and stays
    /// dark on the gray, unfocused selection, which is the standard behavior).
    @Environment(\.backgroundProminence) private var prominence
    private var highlighted: Bool { prominence == .increased }
    private var primaryColor: Color { highlighted ? .white : Tokens.text }
    private var secondaryColor: Color { highlighted ? Color.white.opacity(0.85) : Tokens.textMuted }
    private var faintColor: Color { highlighted ? Color.white.opacity(0.7) : Tokens.textFaint }

    private var todoCounts: TodoCounts {
        TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    private var awaitingMe: Bool {
        TodoHelpers.ballInMyCourt(pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    private var fullyResolved: Bool {
        guard pr.state == .open, todoCounts.total > 0, todoCounts.open == 0 else { return false }
        // Author still owes a fix if CI is red on their own PR.
        if pr.author.login == viewerLogin && pr.ciFail > 0 { return false }
        return true
    }

    private var ciFailedForMe: Bool {
        pr.state == .open && pr.author.login == viewerLogin && pr.ciFail > 0
    }

    private var titleWeight: Font.Weight {
        if awaitingMe { return .bold }
        if fullyResolved || pr.state == .merged { return .medium }
        return .semibold
    }

    private var dimRow: Bool {
        if isSelected { return false }
        if pr.state == .merged { return true }
        if fullyResolved { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TodoRing(done: todoCounts.done, total: todoCounts.total, size: 24, state: ringState, inProgressIcon: "highlighter", highlighted: highlighted)

            VStack(alignment: .leading, spacing: 4) {
                topLine
                bottomLine
                if let hint = preview, !dimRow {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
        .padding(.bottom, 11)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .opacity(dimRow ? 0.55 : 1.0)
    }

    private var ringState: TodoRing.RingState {
        if ciFailedForMe { return .ciFailed }
        if todoCounts.total == 0 { return .empty }
        if todoCounts.open == 0 { return .allResolved }
        if awaitingMe { return .awaitingMe }
        return .waiting
    }

    private var topLine: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(pr.title)
                .font(.system(size: 13, weight: titleWeight))
                .foregroundStyle(primaryColor)
                .tracking(-0.05)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RelativeTimeFormatter.short(pr.updatedAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(faintColor)
                .lineLimit(1)
        }
    }

    private var bottomLine: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 15)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
            Text("·").foregroundStyle(faintColor)
            Text("#\(pr.number)").font(.system(size: 11).monospacedDigit()).foregroundStyle(faintColor)
            Spacer(minLength: 0)
            statusChip
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch chipKind {
        case .merged:
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.merge").font(.system(size: 11).weight(.semibold))
                Text("Merged").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(highlighted ? .white : Lane.recent.color)
        case .ciFailed:
            HStack(spacing: 3) {
                Image(systemName: "xmark.octagon.fill").font(.system(size: 10).weight(.bold))
                Text("CI failed").font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(highlighted ? .white : Tokens.changes)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(highlighted ? Color.white.opacity(0.22) : Tokens.changesBg, in: Capsule())
        case .caughtUp:
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.system(size: 10).weight(.bold))
                Text("Caught up").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(highlighted ? .white : Tokens.approved)
        case .forMe(let count):
            HStack(spacing: 4) {
                Circle().fill(highlighted ? Color.white : Tokens.accent).frame(width: 5, height: 5)
                Text("\(count) for me").font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(highlighted ? .white : Tokens.accent)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(highlighted ? Color.white.opacity(0.22) : Tokens.accentBg, in: Capsule())
        case .waiting:
            Text("waiting on others")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(secondaryColor)
        case .none:
            EmptyView()
        }
    }

    private enum ChipKind { case merged, ciFailed, caughtUp, forMe(Int), waiting, none }

    private var chipKind: ChipKind {
        if pr.state == .merged { return .merged }
        // CI failure on the viewer's own PR takes precedence over caughtUp /
        // forMe — fixing the build is the implicit todo.
        if ciFailedForMe { return .ciFailed }
        if fullyResolved { return .caughtUp }
        if awaitingMe { return .forMe(todoCounts.openMessages) }
        if todoCounts.total > 0 { return .waiting }
        return .none
    }

    /// Preview line: first open non-mine message body, prefixed with the author's first name.
    private var preview: String? {
        let threads = TodoHelpers.threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        for thread in threads where !TodoHelpers.isResolved(thread) {
            for msg in thread.messages where !msg.isMine && !msg.isDone {
                let firstName = (msg.actor.name ?? msg.actor.login).split(separator: " ").first.map(String.init)
                    ?? msg.actor.login
                return "\(firstName): \(msg.body)"
            }
        }
        return pr.attentionHint
    }
}
