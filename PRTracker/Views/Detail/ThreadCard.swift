import SwiftUI

struct ThreadCard: View {
    let thread: Thread
    let onToggleMessageDone: (ThreadMessage) -> Void
    let onResolveAll: () -> Void

    @State private var collapsed: Bool

    init(thread: Thread, onToggleMessageDone: @escaping (ThreadMessage) -> Void, onResolveAll: @escaping () -> Void) {
        self.thread = thread
        self.onToggleMessageDone = onToggleMessageDone
        self.onResolveAll = onResolveAll
        self._collapsed = State(initialValue: TodoHelpers.isResolved(thread))
    }

    private var resolved: Bool { TodoHelpers.isResolved(thread) }
    private var hasNew: Bool { TodoHelpers.hasNew(thread) }
    private var openMessageCount: Int { TodoHelpers.openCount(thread) }
    private var totalNonMine: Int { thread.messages.filter { !$0.isMine }.count }
    private var doneNonMine: Int { thread.messages.filter { !$0.isMine && $0.isDone }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !collapsed {
                Divider().background(Tokens.hairline)
                if let hunk = thread.diffHunk {
                    diffHunkBlock(hunk)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
                ForEach(thread.messages) { msg in
                    ThreadMessageRow(message: msg, onToggleDone: { onToggleMessageDone(msg) })
                }
                if !resolved && totalNonMine > 0 {
                    resolveFooter
                }
            }
        }
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hasNew ? Tokens.accent.opacity(0.4) : Tokens.border, lineWidth: 0.5)
        )
        .shadow(color: resolved ? .clear : Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .opacity(resolved ? 0.78 : 1.0)
        .animation(.easeOut(duration: 0.18), value: collapsed)
    }

    private var header: some View {
        Button { collapsed.toggle() } label: {
            HStack(spacing: 10) {
                statusTile
                VStack(alignment: .leading, spacing: 2) {
                    headerTitleLine
                    Text(subLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.textMuted)
                }
                Spacer(minLength: 0)
                if !resolved && totalNonMine > 1 {
                    Button(action: onResolveAll) {
                        Text("Resolve all")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.textMuted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Tokens.contentBg, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .animation(.easeOut(duration: 0.15), value: collapsed)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerTitleLine: some View {
        HStack(spacing: 6) {
            if let label = thread.kindLabel {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(label == "Changes requested" ? Tokens.changes : Tokens.textMuted)
                Text("·").foregroundStyle(Tokens.textFaint)
            }
            Text(thread.location)
                .font(.system(size: 12.5, weight: .semibold,
                              design: thread.kind == .reviewComment ? .monospaced : .default))
                .foregroundStyle(Tokens.text)
        }
    }

    @ViewBuilder
    private var statusTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(statusTileFill)
                .frame(width: 22, height: 22)
            statusTileLabel
        }
    }

    private var statusTileFill: Color {
        if resolved { return Tokens.approved }
        if hasNew { return Tokens.accent }
        return Tokens.hairline
    }

    @ViewBuilder
    private var statusTileLabel: some View {
        if resolved {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        } else if totalNonMine > 0 {
            Text("\(doneNonMine)/\(totalNonMine)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(hasNew ? .white : Tokens.textMuted)
        }
    }

    private var subLine: String {
        if resolved { return "Resolved" }
        return "\(openMessageCount) open · \(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s")"
    }

    private var resolveFooter: some View {
        Button(action: onResolveAll) {
            Text("Resolve")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Tokens.cardBg)
                .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .top)
        }
        .buttonStyle(.plain)
    }

    /// Renders the diff_hunk snippet (the GitHub-style code excerpt that
    /// anchors a code-comment thread) as a monospaced block with +/- line coloring.
    private func diffHunkBlock(_ hunk: String) -> some View {
        let lines = hunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(diffLineColor(line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
    }

    private func diffLineColor(_ line: String) -> Color {
        let first = line.first
        if first == "+" { return Tokens.approved }
        if first == "-" { return Tokens.changes }
        if line.hasPrefix("@@") { return Tokens.accent }
        return Tokens.textMuted
    }
}
