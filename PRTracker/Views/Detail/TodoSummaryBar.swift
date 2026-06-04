import SwiftUI

struct TodoSummaryBar: View {
    let counts: TodoCounts
    /// True when the viewer is the PR's author and CI is failing. Overrides
    /// "All caught up" with a "CI is failing" treatment so the author isn't
    /// told the PR is done when there's a red build to fix.
    var ciFailedForMe: Bool = false

    private var threadsResolved: Bool { counts.total > 0 && counts.open == 0 }
    private var resolved: Bool { threadsResolved && !ciFailedForMe }

    var body: some View {
        HStack(spacing: 10) {
            TodoRing(done: counts.done, total: counts.total, size: 32, state: ringState, inProgressIcon: "highlighter")
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryColor)
                Text(secondaryLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var ringState: TodoRing.RingState {
        if ciFailedForMe { return .ciFailed }
        return resolved ? .allResolved : .awaitingMe
    }

    private var primaryLine: String {
        if ciFailedForMe { return "CI is failing" }
        if resolved { return "All caught up" }
        return "\(counts.done) of \(counts.total) threads resolved"
    }

    private var secondaryLine: String {
        if ciFailedForMe {
            if threadsResolved { return "No outstanding feedback, but the build is red." }
            let suffix = counts.openMessages == 1 ? "message" : "messages"
            return "Fix the build and address \(counts.openMessages) open \(suffix)."
        }
        if resolved { return "No outstanding feedback. Ready when CI is." }
        let suffix = counts.openMessages == 1 ? "message" : "messages"
        return "\(counts.openMessages) open \(suffix) to address"
    }

    private var primaryColor: Color {
        if ciFailedForMe { return Tokens.changes }
        return resolved ? Tokens.approved : Tokens.accentText
    }

    private var bgColor: Color {
        if ciFailedForMe { return Tokens.changesBg }
        return resolved ? Tokens.approvedBg : Tokens.accentBg
    }

    private var borderColor: Color {
        if ciFailedForMe { return Tokens.changes.opacity(0.27) }
        return resolved ? Tokens.approved.opacity(0.27) : Tokens.accent.opacity(0.2)
    }
}
