import SwiftUI

/// GitHub-style state badge — merged / closed / draft. Open PRs get no pill
/// (`Kind(_:)` returns nil), since "open" is the unremarkable default.
struct PRStatePill: View {
    enum Kind {
        case merged, closed, draft

        init?(_ state: PRState) {
            switch state {
            case .merged: self = .merged
            case .closed: self = .closed
            case .draft:  self = .draft
            case .open:   return nil
            }
        }

        var label: String {
            switch self {
            case .merged: "Merged"
            case .closed: "Closed"
            case .draft:  "Draft"
            }
        }

        var icon: String {
            switch self {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .draft:  "pencil.line"
            }
        }

        var tint: Color {
            switch self {
            case .merged: Lane.recent.color
            case .closed: Tokens.changes
            case .draft:  Tokens.textMuted
            }
        }
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.icon).font(.system(size: 9.5, weight: .semibold))
            Text(kind.label).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(kind.tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(kind.tint.opacity(0.12), in: Capsule())
    }
}
