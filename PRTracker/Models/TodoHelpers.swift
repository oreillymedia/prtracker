import Foundation

// MARK: - Value types

enum ThreadKind: Equatable {
    case reviewComment
    case prComment
}

enum ThreadMessageBacking: Equatable {
    case timelineEvent(eventID: String)
    case reviewComment(commentID: String)
}

struct Thread: Identifiable, Equatable {
    let id: String
    let kind: ThreadKind
    let location: String
    let kindLabel: String?
    /// Diff context for a code-anchored thread (set only when `kind == .reviewComment`).
    let diffHunk: String?
    let messages: [ThreadMessage]
    /// Direct link to this discussion on GitHub. Nil only if we couldn't
    /// construct an anchor (e.g. legacy row with no numeric DB id yet).
    let githubURL: URL?

    init(id: String, kind: ThreadKind, location: String, kindLabel: String?,
         diffHunk: String? = nil, messages: [ThreadMessage], githubURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.location = location
        self.kindLabel = kindLabel
        self.diffHunk = diffHunk
        self.messages = messages
        self.githubURL = githubURL
    }
}

struct ThreadMessage: Identifiable, Equatable {
    let id: String
    let actor: User
    let createdAt: Date
    let body: String
    let isMine: Bool
    let isDone: Bool
    let isNew: Bool
    let underlying: ThreadMessageBacking
}

struct TodoCounts: Equatable {
    let total: Int
    let done: Int
    let open: Int
    let openMessages: Int
}

/// Everything a source-list row needs that is derived from a PR's thread tree.
/// Built once per PR (see `TodoHelpers.rowMeta`) so rows don't each rebuild threads.
struct PRRowMeta: Equatable {
    let counts: TodoCounts
    let ball: Bool
    let preview: String?
}

// MARK: - Helpers

enum TodoHelpers {

    static func threads(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> [Thread] {
        var out: [Thread] = []
        let prURL = "https://github.com/\(pr.repo.id)/pull/\(pr.number)"

        // PR-comment threads: top-level TimelineEvents of type .comment, one message each.
        for e in pr.timeline where e.type == .comment {
            guard let msg = makeMessage(timelineEvent: e, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt) else { continue }
            let url = e.numericID.flatMap { URL(string: "\(prURL)#issuecomment-\($0)") }
                ?? URL(string: prURL)
            out.append(Thread(id: "te_\(e.id)", kind: .prComment,
                              location: "Discussion", kindLabel: nil,
                              messages: [msg], githubURL: url))
        }

        // Review-summary threads: the message attached to an Approve /
        // Changes-Requested / Comment review action (separate from the
        // per-line code comments under the same review).
        for e in pr.timeline where e.type == .review && !(e.body ?? "").isEmpty {
            guard let msg = makeMessage(timelineEvent: e, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt) else { continue }
            let kindLabel: String? = {
                switch e.reviewState {
                case .approved:         return "Approved"
                case .changesRequested: return "Changes requested"
                case .commented, .pending, .none: return nil
                }
            }()
            let url = e.reviewID.flatMap { URL(string: "\(prURL)#pullrequestreview-\($0)") }
                ?? URL(string: prURL)
            out.append(Thread(id: "rv_\(e.id)", kind: .prComment,
                              location: "Discussion", kindLabel: kindLabel,
                              messages: [msg], githubURL: url))
        }

        // Review-comment threads: group by parent review id + chain replies.
        let comments = pr.reviewComments
        let roots = comments.filter { $0.inReplyToID == nil }
        for root in roots.sorted(by: { $0.createdAt < $1.createdAt }) {
            let replies = comments
                .filter { $0.inReplyToID == root.id }
                .sorted { $0.createdAt < $1.createdAt }
            let messages = ([root] + replies).map {
                makeMessage(reviewComment: $0, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
            }
            let kindLabel = originReviewKindLabel(reviewIntegerID: root.parentReviewIntegerID, in: pr)
            let location = root.line.map { "\(root.path) L\($0)" } ?? root.path
            let hunk = root.diffHunk.isEmpty ? nil : root.diffHunk
            let url = root.numericID.flatMap { URL(string: "\(prURL)#discussion_r\($0)") }
                ?? URL(string: prURL)
            out.append(Thread(id: "rc_\(root.id)", kind: .reviewComment,
                              location: location, kindLabel: kindLabel,
                              diffHunk: hunk, messages: messages, githubURL: url))
        }

        return out.sorted { ($0.messages.last?.createdAt ?? .distantPast) > ($1.messages.last?.createdAt ?? .distantPast) }
    }

    nonisolated static func isResolved(_ thread: Thread) -> Bool {
        thread.messages.allSatisfy { $0.isMine || $0.isDone }
    }

    nonisolated static func hasNew(_ thread: Thread) -> Bool {
        thread.messages.contains { !$0.isMine && !$0.isDone && $0.isNew }
    }

    nonisolated static func openCount(_ thread: Thread) -> Int {
        thread.messages.filter { !$0.isMine && !$0.isDone }.count
    }

    static func todoCounts(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> TodoCounts {
        let ts = threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
        let total = ts.count
        let done = ts.filter(isResolved).count
        let openMessages = ts.reduce(0) { $0 + openCount($1) }
        return TodoCounts(total: total, done: done, open: total - done, openMessages: openMessages)
    }

    static func ballInMyCourt(_ pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> Bool {
        if pr.state == .merged || pr.state == .closed { return false }
        let counts = todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
        if counts.openMessages > 0 { return true }
        let mine = pr.author.login == viewerLogin
        if mine && pr.reviewState == .changesRequested { return true }
        // Failing CI on a PR I authored is a todo for me, regardless of comments.
        if mine && pr.ciFail > 0 { return true }
        return false
    }

    /// Builds the PR's thread tree ONCE and derives counts, ball-in-my-court, and
    /// the source-list preview line from it. This is the per-render entry point for
    /// the source list — it folds together what `todoCounts`, `ballInMyCourt`, and
    /// the row's preview logic would otherwise each rebuild from scratch.
    static func rowMeta(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> PRRowMeta {
        let ts = threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)

        let total = ts.count
        let done = ts.filter(isResolved).count
        let openMessages = ts.reduce(0) { $0 + openCount($1) }
        let counts = TodoCounts(total: total, done: done, open: total - done, openMessages: openMessages)

        // Mirror of ballInMyCourt, reusing `counts` so we don't rebuild threads.
        let ball: Bool
        if pr.state == .merged || pr.state == .closed {
            ball = false
        } else if counts.openMessages > 0 {
            ball = true
        } else {
            let mine = pr.author.login == viewerLogin
            ball = mine && (pr.reviewState == .changesRequested || pr.ciFail > 0)
        }

        // Preview: first open non-mine message body, prefixed with the author's
        // first name; falls back to the PR's attentionHint when there's none.
        var preview: String? = pr.attentionHint
        outer: for thread in ts where !isResolved(thread) {
            for msg in thread.messages where !msg.isMine && !msg.isDone {
                let firstName = (msg.actor.name ?? msg.actor.login).split(separator: " ").first.map(String.init) ?? msg.actor.login
                preview = "\(firstName): \(msg.body)"
                break outer
            }
        }

        return PRRowMeta(counts: counts, ball: ball, preview: preview)
    }

    // MARK: - Private

    private static func makeMessage(timelineEvent e: TimelineEvent, viewerLogin: String, lastSeenAt: Date?) -> ThreadMessage? {
        guard let actor = e.actor else { return nil }
        let isMine = actor.login == viewerLogin
        let isNew = !isMine && !e.isDone && (lastSeenAt.map { e.at > $0 } ?? true)
        return ThreadMessage(id: e.id, actor: actor, createdAt: e.at, body: e.body ?? "",
                             isMine: isMine, isDone: e.isDone, isNew: isNew,
                             underlying: .timelineEvent(eventID: e.id))
    }

    private static func makeMessage(reviewComment c: ReviewComment, viewerLogin: String, lastSeenAt: Date?) -> ThreadMessage {
        let isMine = c.author.login == viewerLogin
        let isNew = !isMine && !c.isDone && (lastSeenAt.map { c.createdAt > $0 } ?? true)
        return ThreadMessage(id: c.id, actor: c.author, createdAt: c.createdAt, body: c.body,
                             isMine: isMine, isDone: c.isDone, isNew: isNew,
                             underlying: .reviewComment(commentID: c.id))
    }

    private static func originReviewKindLabel(reviewIntegerID: Int?, in pr: PullRequest) -> String? {
        guard let rid = reviewIntegerID,
              let event = pr.timeline.first(where: { $0.reviewID == rid && $0.type == .review }) else {
            return nil
        }
        return event.reviewState == .changesRequested ? "Changes requested" : nil
    }
}
