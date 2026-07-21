import SwiftUI

struct DetailRightRail: View {
    let pr: PullRequest

    @State private var showCIDetails: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Last activity") {
                    RelativeTimeText(date: pr.lastActivityAt)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.textMuted)
                }
                section("Last checked") {
                    Group {
                        if let fetched = pr.lastFetchedAt {
                            RelativeTimeText(date: fetched)
                        } else {
                            Text("Never")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textMuted)
                }
                section("Repository") {
                    Text(pr.repo.id)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.textMuted)
                }
                section("Status") {
                    row("Review", pill: pr.reviewState?.rawValue ?? "—", tint: reviewTint)
                    row("CI", pill: ciSummary, tint: ciTint)
                    row("Mergeable", pill: mergeableLabel, tint: mergeTint)
                }
                ciChecksSection
                section("Reviewers") {
                    ForEach(reviewersExcludingAuthor) { r in
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
                section("Opened") {
                    RelativeTimeText(date: pr.openedAt)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.textMuted)
                }
                section("Pull Request") {
                    Text("#\(pr.number)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Tokens.textMuted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).railSectionHeader().foregroundStyle(Tokens.textFaint)
            content()
        }
    }

    /// CI Checks section — rolled up by default to a single summary pill;
    /// tap the header to disclose the per-run list.
    @ViewBuilder
    private var ciChecksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showCIDetails.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("CI Checks").railSectionHeader().foregroundStyle(Tokens.textFaint)
                    Image(systemName: showCIDetails ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tokens.textFaint)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCIDetails {
                ForEach(pr.ciChecks) { run in
                    HStack(spacing: 8) {
                        Image(systemName: ciIcon(run.state)).foregroundStyle(ciColor(run.state))
                        Text(run.name).font(.system(size: 12))
                        Spacer()
                        if let d = run.durationSeconds { Text("\(d)s").microText().foregroundStyle(Tokens.textFaint) }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: ciIcon(rollupCIState))
                        .foregroundStyle(ciColor(rollupCIState))
                    Text(ciSummary).font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
                }
            }
        }
    }

    /// GitHub treats anyone who appears in /reviews as a "reviewer," but a PR
    /// author can leave comment-style reviews on their own PR. Excluding the
    /// author here keeps the Reviewers section accurate to actual reviewers.
    private var reviewersExcludingAuthor: [Reviewer] {
        pr.reviewers.filter { $0.user.login != pr.author.login }
    }

    /// Dominant CI state for the collapsed summary icon: fail > running > pass > pending.
    private var rollupCIState: CIState {
        if pr.ciFail > 0 { return .fail }
        if pr.ciRunning > 0 { return .running }
        if pr.ciPass > 0 { return .pass }
        return .pending
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
