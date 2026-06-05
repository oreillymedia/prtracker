import SwiftUI

struct MailRowView: View {
    let pr: PullRequest
    /// Thread-derived data precomputed once per PR by the list (see `TodoHelpers.rowMeta`).
    /// The row never rebuilds threads itself. Optional only defensively — a visible row
    /// always has an entry; nil renders a benign empty row.
    let meta: PRRowMeta?
    let isSelected: Bool
    let viewerLogin: String

    /// True when this is the selected row and the window is active — i.e. when
    /// the blue accent selection capsule (not the gray inactive one) is drawn
    /// behind it, so we flip the row's content to white to read on the accent.
    /// (`backgroundProminence` isn't updated for macOS `.sidebar` lists, so we
    /// derive the state from the selection + window active state instead.)
    @Environment(\.controlActiveState) private var controlActiveState
    private var highlighted: Bool { isSelected && controlActiveState != .inactive }
    private var primaryColor: Color { highlighted ? .white : Tokens.text }
    private var secondaryColor: Color { highlighted ? Color.white.opacity(0.85) : Tokens.textMuted }
    private var faintColor: Color { highlighted ? Color.white.opacity(0.7) : Tokens.textFaint }

    private var counts: TodoCounts { meta?.counts ?? TodoCounts(total: 0, done: 0, open: 0, openMessages: 0) }
    private var awaitingMe: Bool { meta?.ball ?? false }

    private var fullyResolved: Bool {
        guard pr.state == .open, counts.total > 0, counts.open == 0 else { return false }
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
            TodoRing(done: counts.done, total: counts.total, size: 24, state: ringState, inProgressIcon: "highlighter", highlighted: highlighted)

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
        if counts.total == 0 { return .empty }
        if counts.open == 0 { return .allResolved }
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
        if awaitingMe { return .forMe(counts.openMessages) }
        if counts.total > 0 { return .waiting }
        return .none
    }

    /// Preview line: precomputed once per PR by the list (see `TodoHelpers.rowMeta`).
    private var preview: String? { meta?.preview ?? pr.attentionHint }
}
