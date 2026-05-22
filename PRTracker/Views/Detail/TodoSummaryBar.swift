import SwiftUI

struct TodoSummaryBar: View {
    let counts: TodoCounts

    private var resolved: Bool { counts.total > 0 && counts.open == 0 }

    var body: some View {
        HStack(spacing: 10) {
            TodoRing(done: counts.done, total: counts.total, size: 32,
                     state: resolved ? .allResolved : .awaitingMe)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(resolved ? Tokens.approved : Tokens.accentText)
                Text(secondaryLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (resolved ? Tokens.approvedBg : Tokens.accentBg),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(resolved ? Tokens.approved.opacity(0.27) : Tokens.accent.opacity(0.2),
                        lineWidth: 0.5)
        )
    }

    private var primaryLine: String {
        if resolved { return "All caught up" }
        return "\(counts.done) of \(counts.total) threads resolved"
    }

    private var secondaryLine: String {
        if resolved { return "No outstanding feedback. Ready when CI is." }
        let suffix = counts.openMessages == 1 ? "message" : "messages"
        return "\(counts.openMessages) open \(suffix) to address"
    }
}
