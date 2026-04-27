import SwiftUI

struct TimelineEventRow: View {
    let event: TimelineEvent
    var onTap: () -> Void
    var onMarkUpToHere: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Tokens.contentBg).frame(width: 22, height: 22)
                Circle().fill(dotColor).frame(width: 18, height: 18)
                Image(systemName: dotIcon).foregroundStyle(.white).font(.system(size: 10).weight(.bold))
                if !event.isSeen {
                    Circle().stroke(Tokens.accent.opacity(0.22), lineWidth: 4)
                        .frame(width: 22, height: 22)
                }
            }.padding(.leading, 4)

            VStack(alignment: .leading, spacing: 4) {
                header
                if let body = event.body, [.comment, .review].contains(event.type) {
                    Text(body)
                        .font(.system(size: 12.5))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
                }
            }
        }
        .opacity(event.isSeen ? 0.48 : 1.0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Mark up to here as seen", action: onMarkUpToHere)
            Button(event.isSeen ? "Mark unseen" : "Mark seen", action: onTap)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let actor = event.actor { Text(actor.name ?? actor.login).metaText() }
            Text(verb).foregroundStyle(Tokens.textMuted).font(.system(size: 12))
            if let sha = event.sha { Text(sha).monoText().padding(.horizontal, 6).padding(.vertical, 1).background(Tokens.hairline, in: Capsule()) }
            Spacer()
            Text(RelativeTimeFormatter.short(event.at)).microText().foregroundStyle(Tokens.textFaint)
        }
    }

    private var verb: String {
        switch event.type {
        case .commit: "pushed"
        case .opened: "opened this pull request"
        case .review: switch event.reviewState {
            case .approved: "approved"
            case .changesRequested: "requested changes"
            case .commented: "commented on the review"
            default: "left a review"
            }
        case .comment: "commented"
        case .status: "status update"
        case .merged: "merged"
        case .closed: "closed"
        case .assigned: "assigned"
        case .labeled: "labeled"
        }
    }

    private var dotColor: Color {
        switch event.type {
        case .commit: Tokens.commented
        case .opened, .merged: Tokens.approved
        case .review:
            switch event.reviewState {
            case .approved: Tokens.approved
            case .changesRequested: Tokens.changes
            default: Tokens.commented
            }
        case .comment: Tokens.accent
        case .status: Tokens.pending
        default: Tokens.textFaint
        }
    }

    private var dotIcon: String {
        switch event.type {
        case .commit: "circle.dotted"
        case .opened: "arrow.triangle.pull"
        case .review:
            switch event.reviewState {
            case .approved: "checkmark"
            case .changesRequested: "xmark"
            default: "bubble.left"
            }
        case .comment: "bubble.left"
        case .status: "circle.dashed"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark"
        default: "tag"
        }
    }
}
