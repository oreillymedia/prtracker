import Foundation
import SwiftData

@ModelActor
actor SyncActor {
    private func userBy(login: String, ctx: ModelContext) -> User? {
        let predicate = #Predicate<User> { $0.login == login }
        return try? ctx.fetch(FetchDescriptor<User>(predicate: predicate)).first
    }

    private func upsertUser(_ dto: UserDTO, ctx: ModelContext) -> User {
        if let existing = userBy(login: dto.login, ctx: ctx) {
            if let n = dto.name { existing.name = n }
            if let a = dto.avatar_url { existing.avatarURL = a }
            return existing
        }
        let u = User(login: dto.login, name: dto.name, avatarURL: dto.avatar_url)
        ctx.insert(u)
        return u
    }

    private func repoByID(_ id: String, ctx: ModelContext) -> Repo? {
        let target = id
        let predicate = #Predicate<Repo> { $0.id == target }
        return try? ctx.fetch(FetchDescriptor<Repo>(predicate: predicate)).first
    }

    private func prByID(_ id: String, ctx: ModelContext) -> PullRequest? {
        let target = id
        let predicate = #Predicate<PullRequest> { $0.id == target }
        return try? ctx.fetch(FetchDescriptor<PullRequest>(predicate: predicate)).first
    }

    func upsertPullRequests(_ dtos: [PullRequestDTO], inRepoID repoID: String) throws {
        let ctx = modelContext
        guard let repo = repoByID(repoID, ctx: ctx) else { return }

        let dtoIDs = Set(dtos.map(\.node_id))
        let targetRepoID = repoID
        let predicate = #Predicate<PullRequest> { $0.repo.id == targetRepoID }
        let existing = (try? ctx.fetch(FetchDescriptor<PullRequest>(predicate: predicate))) ?? []
        for pr in existing where pr.state == .open && !dtoIDs.contains(pr.id) {
            pr.state = .closed
        }

        for dto in dtos {
            let author = upsertUser(dto.user, ctx: ctx)
            let pr: PullRequest
            if let existingPR = prByID(dto.node_id, ctx: ctx) {
                pr = existingPR
            } else {
                pr = PullRequest(
                    id: dto.node_id, number: dto.number, title: dto.title,
                    state: .open, branchHead: dto.head.ref, branchBase: dto.base.ref,
                    headSha: dto.head.sha, openedAt: dto.created_at, updatedAt: dto.updated_at,
                    author: author, repo: repo)
                ctx.insert(pr)
            }
            pr.title = dto.title
            pr.author = author
            pr.branchHead = dto.head.ref
            pr.branchBase = dto.base.ref
            if pr.headSha != dto.head.sha {
                pr.headSha = dto.head.sha
                for c in pr.ciChecks { ctx.delete(c) }
            }
            pr.additions = dto.additions ?? 0
            pr.deletions = dto.deletions ?? 0
            pr.changedFiles = dto.changed_files ?? 0
            pr.openedAt = dto.created_at
            pr.updatedAt = dto.updated_at
            pr.mergedAt = dto.merged_at
            if dto.draft { pr.state = .draft }
            else if dto.merged_at != nil { pr.state = .merged }
            else if dto.state == "open" { pr.state = .open }
            else { pr.state = .closed }
            pr.mergeable = dto.mergeable_state.flatMap { Mergeable(rawValue: $0.uppercased()) } ?? .unknown

            for l in pr.labels { ctx.delete(l) }
            for ldto in dto.labels { ctx.insert(Label(name: ldto.name, pr: pr)) }

            // Reviewers: union of currently-requested reviewers (pending) and
            // anyone who already submitted a review (state preserved). We only
            // remove pending stand-ins that GitHub no longer lists as requested;
            // real review states stick until updateReviewerStates overwrites them.
            let requestedLogins = Set((dto.requested_reviewers ?? []).map(\.login))
            for r in pr.reviewers where r.state == .pending && !requestedLogins.contains(r.user.login) {
                ctx.delete(r)
            }
            let existingLogins = Set(pr.reviewers.map(\.user.login))
            for ureq in dto.requested_reviewers ?? [] where !existingLogins.contains(ureq.login) {
                let reviewUser = upsertUser(ureq, ctx: ctx)
                ctx.insert(Reviewer(user: reviewUser, state: .pending, pr: pr))
            }
        }

        repo.lastFetchedAt = .now
        try ctx.save()
    }

    func upsertCIChecks(prID: String, dto: CheckRunsResponseDTO) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        for c in pr.ciChecks { ctx.delete(c) }
        var pass = 0, fail = 0, running = 0, pending = 0
        for r in dto.check_runs {
            let state: CIState = {
                if r.status == "completed" {
                    // GitHub conclusions: success, failure, neutral, cancelled,
                    // skipped, timed_out, action_required, stale.
                    switch r.conclusion {
                    case "success", "neutral", "skipped":
                        return .pass
                    case "failure", "timed_out", "cancelled", "action_required":
                        return .fail
                    case "stale":
                        // Stale results are inconclusive; treat as pending so the
                        // user knows the run is not authoritative.
                        return .pending
                    default:
                        // Unknown conclusions and `nil` for completed status are
                        // surfaced as pending rather than silently passing.
                        return .pending
                    }
                }
                if r.status == "in_progress" { return .running }
                return .pending
            }()
            switch state {
            case .pass: pass += 1
            case .fail: fail += 1
            case .running: running += 1
            case .pending: pending += 1
            }
            let dur: Int? = {
                guard let s = r.started_at, let e = r.completed_at else { return nil }
                return Int(e.timeIntervalSince(s))
            }()
            ctx.insert(CIRun(name: r.name, state: state, pr: pr, durationSeconds: dur))
        }
        pr.ciPass = pass; pr.ciFail = fail; pr.ciRunning = running; pr.ciPending = pending
        pr.ciTotal = dto.total_count
        try ctx.save()
    }

    /// Upsert per-line review comments fetched from /pulls/{n}/comments.
    /// `id` surrogate is `node_id` if present, else "RC_<integer>". Existing
    /// rows have their body/path/line/diffHunk refreshed; `isSeen` and
    /// `createdAt` are preserved. Anything previously stored for this PR
    /// that isn't in the response is purged.
    func upsertReviewComments(prID: String, fromDTOs comments: [ReviewCommentDTO]) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }

        var byID: [String: ReviewComment] = [:]
        for c in pr.reviewComments { byID[c.id] = c }

        var seenIDs: Set<String> = []
        for dto in comments {
            let cid = dto.node_id ?? "RC_\(dto.id)"
            seenIDs.insert(cid)
            let resolvedLine = dto.line ?? dto.original_line
            let replyTo: String? = {
                guard let r = dto.in_reply_to_id else { return nil }
                // Match the same surrogate scheme used for ids. We assume the
                // parent comment is in the same payload; if not, the link is
                // best-effort.
                if let parent = comments.first(where: { $0.id == r }) {
                    return parent.node_id ?? "RC_\(r)"
                }
                return "RC_\(r)"
            }()

            if let existing = byID[cid] {
                existing.body = dto.body
                existing.path = dto.path
                existing.line = resolvedLine
                existing.diffHunk = dto.diff_hunk
                existing.parentReviewIntegerID = dto.pull_request_review_id
                existing.inReplyToID = replyTo
                // isSeen and createdAt preserved deliberately.
            } else {
                let author = upsertUser(dto.user, ctx: ctx)
                let comment = ReviewComment(
                    id: cid,
                    parentReviewIntegerID: dto.pull_request_review_id,
                    inReplyToID: replyTo,
                    author: author,
                    body: dto.body,
                    path: dto.path,
                    line: resolvedLine,
                    diffHunk: dto.diff_hunk,
                    createdAt: dto.created_at,
                    isSeen: false,
                    pullRequest: pr)
                ctx.insert(comment)
            }
        }
        for c in pr.reviewComments where !seenIDs.contains(c.id) {
            ctx.delete(c)
        }
        try ctx.save()
    }

    func upsertTimeline(prID: String, items: [TimelineItemDTO]) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        var byID: [String: TimelineEvent] = [:]
        for e in pr.timeline { byID[e.id] = e }

        var seenIDs: Set<String> = []
        for dto in items {
            guard let id = dto.node_id ?? dto.id.map({ "TI_\($0)" }) else { continue }
            seenIDs.insert(id)
            let typ: EventType = {
                switch dto.event {
                case "commented": return .comment
                case "reviewed": return .review
                case "committed": return .commit
                case "labeled": return .labeled
                case "merged": return .merged
                case "closed": return .closed
                case "assigned": return .assigned
                default: return .status
                }
            }()
            let parentReviewID: Int? = (typ == .review) ? dto.id : nil
            let actorUser = dto.effectiveActor.map { upsertUser($0, ctx: ctx) }
            let revState = dto.state.flatMap { ReviewState(rawValue: $0) }
            let effectiveAt = dto.effectiveDate
            // Commits put the commit message in `message`, not `body`. Pull
            // whichever is non-nil so commit rows can show the message.
            let effectiveBody = dto.body ?? dto.message
            if let e = byID[id] {
                e.body = effectiveBody ?? e.body
                e.actor = actorUser ?? e.actor
                if let at = effectiveAt { e.at = at }
                if let s = dto.sha { e.sha = s }
                e.reviewState = revState ?? e.reviewState
                e.reviewID = parentReviewID ?? e.reviewID
                // isSeen preserved deliberately
            } else {
                let e = TimelineEvent(
                    id: id, type: typ, at: effectiveAt ?? .now,
                    pullRequest: pr, actor: actorUser,
                    body: effectiveBody, sha: dto.sha, reviewState: revState, isSeen: false)
                e.reviewID = parentReviewID
                ctx.insert(e)
            }
        }
        for e in pr.timeline where !seenIDs.contains(e.id) {
            ctx.delete(e)
        }
        try ctx.save()
    }

    /// Patches diffstat-only fields on a PR from a detail-endpoint fetch.
    /// Other fields are not touched (they're owned by the list-fetch upsert).
    func updatePRStatistics(prID: String, dto: PullRequestDTO) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        pr.additions = dto.additions ?? pr.additions
        pr.deletions = dto.deletions ?? pr.deletions
        pr.changedFiles = dto.changed_files ?? pr.changedFiles
        if let ms = dto.mergeable_state {
            pr.mergeable = Mergeable(rawValue: ms.uppercased()) ?? pr.mergeable
        }
        try ctx.save()
    }

    func setSeen(eventID: String, isSeen: Bool) throws {
        let ctx = modelContext
        let target = eventID
        let predicate = #Predicate<TimelineEvent> { $0.id == target }
        guard let e = try ctx.fetch(FetchDescriptor<TimelineEvent>(predicate: predicate)).first else { return }
        e.isSeen = isSeen
        try ctx.save()
    }

    func setSeenForPR(prID: String, isSeen: Bool) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        for e in pr.timeline { e.isSeen = isSeen }
        for c in pr.reviewComments { c.isSeen = isSeen }
        try ctx.save()
    }

    func setSeenUpTo(prID: String, throughEventID eventID: String) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx),
              let target = pr.timeline.first(where: { $0.id == eventID }) else { return }
        for e in pr.timeline where e.at <= target.at { e.isSeen = true }
        // Cascade to review comments whose parent review event is at-or-before
        // the target's timestamp. We look the parent reviews up by reviewID.
        let cutoffReviewIDs = Set(
            pr.timeline
                .filter { $0.at <= target.at && $0.type == .review }
                .compactMap(\.reviewID)
        )
        for c in pr.reviewComments where c.parentReviewIntegerID.map(cutoffReviewIDs.contains) == true {
            c.isSeen = true
        }
        try ctx.save()
    }

    func setLastReadAt(prID: String, date: Date?) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        pr.lastReadAt = date
        try ctx.save()
    }

    func setSeen(reviewCommentID: String, isSeen: Bool) throws {
        let ctx = modelContext
        let target = reviewCommentID
        let predicate = #Predicate<ReviewComment> { $0.id == target }
        guard let c = try ctx.fetch(FetchDescriptor<ReviewComment>(predicate: predicate)).first else { return }
        c.isSeen = isSeen
        try ctx.save()
    }

    /// Apply submitted reviews to `pr.reviewers`. `/pulls/{n}/reviews` returns
    /// every review event; per GitHub's semantics, only a subsequent decisive
    /// review (APPROVED or CHANGES_REQUESTED) overrides a prior decisive one —
    /// later COMMENTED reviews do not undo an approval. So per reviewer we
    /// pick the most recent decisive review, falling back to the most recent
    /// review of any kind if none decisive exists.
    func upsertReviewerStates(prID: String, fromReviews reviews: [ReviewDTO]) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }

        var byUser: [String: [ReviewDTO]] = [:]
        for r in reviews { byUser[r.user.login, default: []].append(r) }

        var current: [String: ReviewDTO] = [:]
        for (login, list) in byUser {
            let sorted = list.sorted { ($0.submitted_at ?? .distantPast) > ($1.submitted_at ?? .distantPast) }
            current[login] = sorted.first(where: { $0.state == "APPROVED" || $0.state == "CHANGES_REQUESTED" })
                ?? sorted.first
        }

        for (login, dto) in current {
            guard let state = ReviewState(rawValue: dto.state) else { continue }
            if let existing = pr.reviewers.first(where: { $0.user.login == login }) {
                existing.state = state
            } else {
                let reviewUser = upsertUser(dto.user, ctx: ctx)
                ctx.insert(Reviewer(user: reviewUser, state: state, pr: pr))
            }
        }
        try ctx.save()
    }
}
