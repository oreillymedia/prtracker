import SwiftUI

struct TimelineEventRow: View {
    let event: TimelineEvent
    let reviewComments: [ReviewComment]
    let syncActor: SyncActor
    var onTap: () -> Void
    var onMarkUpToHere: () -> Void

    private var hasCard: Bool {
        (event.type == .comment || event.type == .review) && (event.body?.isEmpty == false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dot.padding(.leading, 4)

            VStack(alignment: .leading, spacing: 8) {
                if hasCard {
                    cardContent
                } else {
                    inlineContent
                }

                if event.type == .review {
                    nestedThreads
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

    // MARK: - Dot

    private var dot: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Tokens.contentBg, lineWidth: 2))
                .overlay(Circle().stroke(Tokens.accent.opacity(0.22), lineWidth: 3).opacity(event.isSeen ? 0 : 1))
            Image(systemName: dotIcon).foregroundStyle(.white).font(.system(size: 10).weight(.bold))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Tokens.accent)
                .frame(width: 4)
                // -8 = -4 design target + cancels the HStack's 4pt leading padding
                .offset(x: -8)
                .opacity(event.isSeen ? 0 : 1)
        }
    }

    // MARK: - Card content (comment / review with body)

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let actor = event.actor {
                    AvatarView(user: actor, size: 20)
                    Text(actor.name ?? actor.login)
                        .font(.system(size: 12).weight(.semibold))
                        .foregroundStyle(Tokens.text)
                }
                if event.type == .review, let r = event.reviewState {
                    reviewPill(r)
                }
                Spacer()
                Text(RelativeTimeFormatter.short(event.at))
                    .microText()
                    .foregroundStyle(Tokens.textFaint)
            }
            if let body = event.body, !body.isEmpty {
                MarkdownText(raw: body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
    }

    // MARK: - Inline content (everything else)

    private var inlineContent: some View {
        HStack(spacing: 6) {
            if let actor = event.actor {
                AvatarView(user: actor, size: 18)
                Text(actor.name ?? actor.login)
                    .font(.system(size: 12).weight(.semibold))
                    .foregroundStyle(Tokens.text)
            }
            Text(verb)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.textMuted)
            if event.type == .commit, let body = event.body, !body.isEmpty {
                Text(firstLine(body))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.text)
                    .lineLimit(1)
            }
            if let sha = event.sha, !sha.isEmpty {
                Text(String(sha.prefix(7)))
                    .monoText()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(Tokens.textFaint)
            }
            Spacer()
            Text(RelativeTimeFormatter.short(event.at))
                .microText()
                .foregroundStyle(Tokens.textFaint)
        }
        .padding(.top, 2)
    }

    // MARK: - Pills / labels / icons

    private func reviewPill(_ r: ReviewState) -> some View {
        let (text, color): (String, Color) = {
            switch r {
            case .approved:         ("approved",         Tokens.approved)
            case .changesRequested: ("changes requested", Tokens.changes)
            case .commented:        ("commented",        Tokens.commented)
            case .pending:          ("pending",          Tokens.textFaint)
            }
        }()
        return Text(text)
            .font(.system(size: 10.5).weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func firstLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    }

    private var verb: String {
        switch event.type {
        case .commit:   "pushed"
        case .opened:   "opened this pull request"
        case .review:
            switch event.reviewState {
            case .approved:         "approved"
            case .changesRequested: "requested changes"
            case .commented:        "commented on the review"
            default:                "left a review"
            }
        case .comment:  "commented"
        case .status:   "status update"
        case .merged:   "merged"
        case .closed:   "closed"
        case .assigned: "assigned"
        case .labeled:  "labeled"
        }
    }

    private var dotColor: Color {
        switch event.type {
        case .commit:           Tokens.commented
        case .opened, .merged:  Tokens.approved
        case .review:
            switch event.reviewState {
            case .approved:         Tokens.approved
            case .changesRequested: Tokens.changes
            default:                Tokens.commented
            }
        case .comment:  Tokens.accent
        case .status:   Tokens.pending
        default:        Tokens.textFaint
        }
    }

    private var dotIcon: String {
        switch event.type {
        case .commit:   "circle.dotted"
        case .opened:   "arrow.triangle.pull"
        case .review:
            switch event.reviewState {
            case .approved:         "checkmark"
            case .changesRequested: "xmark"
            default:                "bubble.left"
            }
        case .comment:  "bubble.left"
        case .status:   "circle.dashed"
        case .merged:   "arrow.triangle.merge"
        case .closed:   "xmark"
        default:        "tag"
        }
    }

    // MARK: - Nested review comment threads

    @ViewBuilder
    private var nestedThreads: some View {
        let roots = reviewComments
            .filter { $0.inReplyToID == nil }
            .sorted { $0.createdAt < $1.createdAt }
        if !roots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(roots) { root in
                    let replies = reviewComments
                        .filter { $0.inReplyToID == root.id }
                        .sorted { $0.createdAt < $1.createdAt }
                    ReviewCommentThreadView(root: root, replies: replies, syncActor: syncActor)
                }
            }
            // Absorb taps so they don't bubble to the parent row's onTapGesture
            // and silently toggle the parent review event's seen state.
            .onTapGesture {}
        }
    }
}
