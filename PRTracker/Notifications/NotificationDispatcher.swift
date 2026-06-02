import Foundation
import SwiftData
import UserNotifications

final class NotificationDispatcher {
    private let modelContainer: ModelContainer
    private let poster: NotificationPoster
    private let auth: NotificationAuthorizing
    private let activity: AppActivityProbing

    init(modelContainer: ModelContainer, poster: NotificationPoster, auth: NotificationAuthorizing = NotificationAuthorization(), activity: AppActivityProbing = NSAppActivityProbe()) {
        self.modelContainer = modelContainer
        self.poster = poster
        self.auth = auth
        self.activity = activity
    }

    func process(repoID: String) async {
        let ctx = ModelContext(modelContainer)
        guard let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first else { return }
        if vs.notificationLevel == .none { return }
        if await auth.currentStatus() != .authorized { return }
        if await MainActor.run(body: { activity.isFrontmost() }) { return }
        guard let viewerLogin = vs.viewer?.login else { return }

        let level = vs.notificationLevel
        let prs = (try? ctx.fetch(FetchDescriptor<PullRequest>(
            predicate: #Predicate { $0.repo.id == repoID }))) ?? []

        for pr in prs {
            let prCtx = PRContext(
                id: pr.id,
                authorLogin: pr.author.login,
                viewerHasCommented: viewerHasCommented(on: pr, viewerLogin: viewerLogin))
            let existing = Set(pr.notificationLogs.map(\.id))

            let candidates = collectCandidates(pr: pr, existing: existing)
            let filtered = candidates.filter { candidate in
                NotificationPolicy.shouldNotify(level: level,
                                                candidate: candidate.kind,
                                                pr: prCtx,
                                                viewerLogin: viewerLogin)
            }

            if filtered.isEmpty { continue }

            let content: UNNotificationContent =
                filtered.count == 1
                ? specificContent(filtered[0], pr: pr)
                : aggregateContent(count: filtered.count, pr: pr)

            await poster.post(content)

            for c in filtered {
                ctx.insert(NotificationLog(id: idFor(c),
                                           kind: kindFor(c),
                                           notifiedAt: .now,
                                           pullRequest: pr))
            }
        }

        try? ctx.save()
    }

    private func viewerHasCommented(on pr: PullRequest, viewerLogin: String) -> Bool {
        if pr.timeline.contains(where: { $0.type == .comment && $0.actor?.login == viewerLogin }) { return true }
        if pr.reviewComments.contains(where: { $0.author.login == viewerLogin }) { return true }
        return false
    }

    private func collectCandidates(pr: PullRequest, existing: Set<String>) -> [NotificationCandidate] {
        var out: [NotificationCandidate] = []

        for event in pr.timeline where event.type == .comment {
            if existing.contains("comment_\(event.id)") { continue }
            let author = event.actor?.login ?? "unknown"
            out.append(NotificationCandidate(
                kind: .issueComment(eventID: event.id, authorLogin: author, body: event.body ?? ""),
                prID: pr.id))
        }

        let byID = Dictionary(uniqueKeysWithValues: pr.reviewComments.map { ($0.id, $0) })
        for rc in pr.reviewComments {
            if existing.contains("comment_\(rc.id)") { continue }
            let inReplyToAuthor: String? = rc.inReplyToID.flatMap { byID[$0]?.author.login }
            out.append(NotificationCandidate(
                kind: .codeComment(commentID: rc.id,
                                   authorLogin: rc.author.login,
                                   inReplyToAuthorLogin: inReplyToAuthor,
                                   body: rc.body, path: rc.path, line: rc.line),
                prID: pr.id))
        }

        for event in pr.timeline where event.type == .review {
            if existing.contains("review_\(event.id)") { continue }
            let author = event.actor?.login ?? "unknown"
            let state = event.reviewState ?? .commented
            out.append(NotificationCandidate(
                kind: .reviewSubmitted(eventID: event.id, authorLogin: author, state: state),
                prID: pr.id))
        }

        for run in pr.ciChecks where run.state == .fail {
            guard let runID = run.checkRunID else { continue }
            if existing.contains("ci_\(runID)") { continue }
            out.append(NotificationCandidate(kind: .ciFailure(runID: runID), prID: pr.id))
        }

        let stateID = "state_\(pr.id)_\(pr.state.rawValue)"
        if !existing.contains(stateID),
           [PRState.merged, .closed].contains(pr.state) {
            out.append(NotificationCandidate(kind: .stateChange(newState: pr.state, actorLogin: nil), prID: pr.id))
        }

        let pushID = "push_\(pr.id)_\(pr.headSha)"
        if !existing.contains(pushID) {
            out.append(NotificationCandidate(kind: .headPushed(headSha: pr.headSha, actorLogin: nil), prID: pr.id))
        }

        if !existing.contains("opened_\(pr.id)") {
            out.append(NotificationCandidate(kind: .opened(authorLogin: pr.author.login), prID: pr.id))
        }

        return out
    }

    private func specificContent(_ c: NotificationCandidate, pr: PullRequest) -> UNNotificationContent {
        let title = "\(pr.repo.id) #\(pr.number)"
        let m = UNMutableNotificationContent()
        m.title = title
        m.threadIdentifier = pr.id
        m.userInfo = ["prID": pr.id]
        m.sound = .default
        switch c.kind {
        case .issueComment(_, let author, let body):
            m.body = "\(author): \(body.prefix(200))"
        case .codeComment(_, let author, _, let body, let path, let line):
            let loc = line.map { "\(path):\($0)" } ?? path
            m.body = "\(author) commented on \(loc): \(body.prefix(200))"
        case .reviewSubmitted(_, let author, let state):
            let verb: String = {
                switch state {
                case .approved:         return "approved"
                case .changesRequested: return "requested changes on"
                case .commented:        return "reviewed"
                case .pending:          return "reviewed"
                }
            }()
            m.body = "\(author) \(verb) '\(pr.title)'"
        case .ciFailure:
            m.body = "CI failed on '\(pr.title)'"
        case .stateChange(let newState, let actor):
            let verb: String = {
                switch newState {
                case .merged: return "merged"
                case .closed: return "closed"
                case .open:   return "reopened"
                case .draft:  return "moved to draft"
                }
            }()
            m.body = "\(actor ?? "Someone") \(verb) '\(pr.title)'"
        case .headPushed(_, let actor):
            m.body = "\(actor ?? "Someone") pushed new commits to '\(pr.title)'"
        case .opened(let author):
            m.body = "\(author) opened '\(pr.title)'"
        }
        return m
    }

    private func aggregateContent(count: Int, pr: PullRequest) -> UNNotificationContent {
        let m = UNMutableNotificationContent()
        m.title = "\(pr.repo.id) #\(pr.number)"
        m.body = "\(count) updates on '\(pr.title)'"
        m.threadIdentifier = pr.id
        m.userInfo = ["prID": pr.id]
        m.sound = .default
        return m
    }

    private func idFor(_ c: NotificationCandidate) -> String {
        logIDFromKind(c.kind, prID: c.prID)
    }

    private func logIDFromKind(_ k: NotificationCandidate.Kind, prID: String) -> String {
        switch k {
        case .issueComment(let eventID, _, _): return "comment_\(eventID)"
        case .codeComment(let commentID, _, _, _, _, _): return "comment_\(commentID)"
        case .reviewSubmitted(let eventID, _, _): return "review_\(eventID)"
        case .ciFailure(let runID): return "ci_\(runID)"
        case .stateChange(let newState, _): return "state_\(prID)_\(newState.rawValue)"
        case .headPushed(let sha, _): return "push_\(prID)_\(sha)"
        case .opened: return "opened_\(prID)"
        }
    }

    private func kindFor(_ c: NotificationCandidate) -> String {
        switch c.kind {
        case .issueComment, .codeComment: return "comment"
        case .reviewSubmitted: return "review"
        case .ciFailure: return "ci_failure"
        case .stateChange: return "state_change"
        case .headPushed: return "push"
        case .opened: return "opened"
        }
    }

    func backfillSilentBaseline() async {
        let ctx = ModelContext(modelContainer)
        let prs = (try? ctx.fetch(FetchDescriptor<PullRequest>())) ?? []
        for pr in prs {
            let existing = Set(pr.notificationLogs.map(\.id))
            for c in collectCandidates(pr: pr, existing: existing) {
                let id = idFor(c)
                ctx.insert(NotificationLog(id: id, kind: kindFor(c), notifiedAt: .now, pullRequest: pr))
            }
        }
        try? ctx.save()
    }
}
