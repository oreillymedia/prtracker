import SwiftUI

struct DetailRightRail: View {
    let pr: PullRequest
    var onMarkAllSeen: () -> Void
    var onMarkAllUnseen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Status") {
                row("Review", pill: pr.reviewState?.rawValue ?? "—", tint: reviewTint)
                row("CI", pill: ciSummary, tint: ciTint)
                row("Mergeable", pill: mergeableLabel, tint: mergeTint)
            }
            section("CI checks") {
                ForEach(pr.ciChecks) { run in
                    HStack(spacing: 8) {
                        Image(systemName: ciIcon(run.state)).foregroundStyle(ciColor(run.state))
                        Text(run.name).font(.system(size: 12))
                        Spacer()
                        if let d = run.durationSeconds { Text("\(d)s").microText().foregroundStyle(Tokens.textFaint) }
                    }
                }
            }
            section("Reviewers") {
                ForEach(pr.reviewers) { r in
                    HStack(spacing: 8) {
                        AvatarView(user: r.user, size: 18)
                        Text(r.user.name ?? r.user.login).metaText()
                        Spacer()
                        Text(r.state.rawValue).microText().foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            section("Labels") {
                FlowLayout(spacing: 6) {
                    ForEach(pr.labels) { l in
                        Text(l.name).microText().padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Tokens.hairline, in: Capsule()).foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            section("Changes") {
                HStack(spacing: 6) {
                    Text("+\(pr.additions)").foregroundStyle(Tokens.approved)
                    Text("−\(pr.deletions)").foregroundStyle(Tokens.changes)
                    Text("· \(pr.changedFiles) files").foregroundStyle(Tokens.textFaint)
                }.font(.system(size: 12))
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Mark all seen") { onMarkAllSeen() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Mark all unseen") { onMarkAllUnseen() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(width: 260)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .leading)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).railSectionHeader().foregroundStyle(Tokens.textFaint)
            content()
        }
    }

    private func row(_ label: String, pill: String, tint: Color) -> some View {
        HStack { Text(label).font(.system(size: 12)); Spacer()
            Text(pill).microText().padding(.horizontal, 8).padding(.vertical, 2)
                .background(tint.opacity(0.18), in: Capsule()).foregroundStyle(tint)
        }
    }

    private var reviewTint: Color {
        switch pr.reviewState {
        case .approved: Tokens.approved; case .changesRequested: Tokens.changes
        case .commented: Tokens.commented; default: Tokens.textFaint
        }
    }

    private var ciSummary: String {
        if pr.ciTotal == 0 { return "—" }
        if pr.ciFail > 0 { return "\(pr.ciFail) failed" }
        if pr.ciRunning > 0 { return "\(pr.ciRunning) running" }
        return "\(pr.ciPass)/\(pr.ciTotal) passed"
    }

    private var ciTint: Color { pr.ciFail > 0 ? Tokens.changes : (pr.ciRunning > 0 ? Tokens.pending : Tokens.approved) }

    /// Mergeable display reflects the PR's overall state for closed/merged
    /// PRs (where GitHub's mergeable_state is meaningless), and the actual
    /// mergeable status for open ones.
    private var mergeableLabel: String {
        switch pr.state {
        case .merged: "Merged"
        case .closed: "Closed"
        case .draft:  "Draft"
        case .open:
            switch pr.mergeable {
            case .clean:     "Clean"
            case .conflicts: "Conflicts"
            case .blocked:   "Blocked"
            case .unknown:   "Checking…"
            }
        }
    }

    private var mergeTint: Color {
        switch pr.state {
        case .merged: return Lane.recent.color   // violet — same lane as "Recently merged"
        case .closed: return Tokens.textFaint
        case .draft:  return Tokens.textMuted
        case .open:
            switch pr.mergeable {
            case .clean:     return Tokens.approved
            case .conflicts: return Tokens.changes
            case .blocked:   return Tokens.changes
            case .unknown:   return Tokens.textFaint
            }
        }
    }

    private func ciIcon(_ s: CIState) -> String {
        switch s { case .pass: "checkmark.circle.fill"; case .fail: "xmark.circle.fill"; case .running: "arrow.triangle.2.circlepath"; case .pending: "circle" }
    }

    private func ciColor(_ s: CIState) -> Color {
        switch s { case .pass: Tokens.approved; case .fail: Tokens.changes; case .running: Tokens.pending; case .pending: Tokens.textFaint }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
