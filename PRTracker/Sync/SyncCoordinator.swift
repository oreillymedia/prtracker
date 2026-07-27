import Foundation
import SwiftData
import AppKit

@Observable
final class SyncCoordinator {
    let client: GitHubClient
    let syncActor: SyncActor
    private let modelContainer: ModelContainer

    var isSyncing: Bool = false
    /// Time of the last pass in which *every* enabled repo synced successfully.
    /// Only a full success advances it, so a persistently-failing repo can't be
    /// masked by a healthy one showing a fresh "Updated just now".
    var lastSyncAt: Date?
    var lastSyncError: GitHubError?
    /// Sticky "the stored token is dead" state, set on a GitHub 401. Unlike
    /// `lastSyncError` (transient — network, decoding, rate limit) a 401 will
    /// never resolve by retrying, so it's modeled separately: the sync loops
    /// pause while it's set, and it clears only when a fresh token validates via
    /// `reconnected()`. The main window surfaces it as a Reconnect banner.
    var needsReauth: Bool = false
    var notificationDispatcher: NotificationDispatcher?
    var badgeController: BadgeController?

    // MARK: Priority lane (the PR currently open in the detail view)
    /// True while the priority lane is fetching the selected PR. Drives the
    /// detail view's inline spinner.
    var isRefreshingDetail: Bool = false
    /// Last error from a priority-lane fetch, surfaced in the detail view.
    var lastDetailError: GitHubError?

    private var task: Task<Void, Never>?
    private var priorityTask: Task<Void, Never>?
    private var foregroundIntervalSec: TimeInterval = 120
    private var backgroundIntervalSec: TimeInterval = 300
    /// How often the open PR's threads/CI re-poll. Faster than the whole-repo
    /// loop so conversation updates on the PR you're reading appear promptly,
    /// but routed through the same SyncActor upserts so list and detail agree.
    private let priorityIntervalSec: TimeInterval = 30
    private var isBackgroundMode = false
    /// The PR currently open in the detail view, if any.
    private var prioritySelection: PrioritySelection?
    /// Set when a refresh is requested while one is already running, so the
    /// in-flight pass is followed by one more instead of being silently dropped.
    private var pendingRefresh = false

    struct PrioritySelection: Sendable, Equatable {
        let prID: String
        let ref: RepoRef
        let number: Int
    }

    init(client: GitHubClient, syncActor: SyncActor, modelContainer: ModelContainer) {
        self.client = client
        self.syncActor = syncActor
        self.modelContainer = modelContainer
        observeLifecycle()
    }

    func setIntervals(foregroundMinutes: Int) {
        foregroundIntervalSec = TimeInterval(max(1, foregroundMinutes) * 60)
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in await self?.loop() }
        priorityTask?.cancel()
        priorityTask = Task { [weak self] in await self?.priorityLoop() }
    }

    func stop() {
        task?.cancel(); task = nil
        priorityTask?.cancel(); priorityTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await refresh()
            let interval = isBackgroundMode ? backgroundIntervalSec : foregroundIntervalSec
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Called after the user validates a fresh token in the Reconnect sheet.
    /// Clears the sticky reauth state and any stale error, then kicks an
    /// immediate sync so the paused loop doesn't idle a full interval first.
    func reconnected() {
        needsReauth = false
        lastSyncError = nil
        lastDetailError = nil
        Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        // A dead token can't succeed; the loops keep ticking but do no work
        // until the user reconnects (which flips this off before calling us).
        if needsReauth { return }
        // Coalesce a refresh requested mid-sync into a single follow-up pass
        // rather than dropping it — a manual "Refresh now" during a background
        // cycle should still take effect.
        if isSyncing { pendingRefresh = true; return }
        isSyncing = true
        // Reset once for the whole (possibly coalesced) refresh, not per pass, so
        // a later pass can't silently erase an earlier pass's error.
        lastSyncError = nil
        defer { isSyncing = false }
        repeat {
            pendingRefresh = false
            await performRefresh()
        } while pendingRefresh
    }

    private func performRefresh() async {
        let ctx = ModelContext(modelContainer)
        let enabled = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isEnabled == true }))) ?? []
        if enabled.isEmpty { return }

        var allSucceeded = true
        for repo in enabled {
            let ref = RepoRef(owner: repo.owner, name: repo.name)
            // A repo needs a silent baseline (record current state without
            // posting) until its threads have been fetched and baselined once —
            // covers a never-synced repo AND the first run after thread polling
            // was added to existing installs. Both avoid a backlog flood.
            let needsBaseline = repo.lastFetchedAt == nil || !repo.didBaselineThreads
            do {
                try await refreshRepo(ref: ref, repoID: repo.id, needsBaseline: needsBaseline)
            } catch let e as GitHubError {
                // A 401 is terminal, not transient: flag the dead token so the
                // loop pauses and the banner appears, rather than logging it as
                // just another "sync failed" that keeps retrying every cycle.
                if e == .unauthorized { needsReauth = true } else { lastSyncError = e }
                allSucceeded = false
            } catch {
                lastSyncError = .network(message: error.localizedDescription)
                allSucceeded = false
            }
        }
        // Advance the global "Updated" time only when the whole set refreshed —
        // an honest "everything is at least this fresh" signal.
        if allSucceeded { lastSyncAt = .now }
    }

    /// Sync a single repo: fetch its open + recently-merged PRs, upsert them,
    /// then refresh CI checks and threads (timeline/reviews/review comments) for
    /// every open PR, and run notifications for the repo. A thrown error aborts
    /// only this repo; `refresh()` continues to the next.
    ///
    /// Threads are fetched for *every* open PR every cycle rather than only for
    /// PRs whose `updated_at` moved: GitHub doesn't reliably bump a PR's
    /// `updated_at` for inline review comments, so a change-filter would silently
    /// miss exactly the review feedback we most want to surface. Conditional
    /// ETags make the unchanged ones cheap (a 304 doesn't count against the rate
    /// limit), so correctness wins without a real cost.
    private func refreshRepo(ref: RepoRef, repoID: String, needsBaseline: Bool) async throws {
        async let openReq = client.listOpenPRs(repo: ref)
        async let recentReq = client.listRecentlyMerged(repo: ref, limit: 20)
        // nil == 304: the list representation is unchanged.
        let (openDTOs, closedDTOs) = try await (openReq, recentReq)

        // Only a fresh open list is authoritative enough to close PRs it omits.
        if let openDTOs {
            try await syncActor.upsertPullRequests(openDTOs, inRepoID: repoID, reconcileOpen: true)
        }
        if let closedDTOs {
            try await syncActor.upsertPullRequests(closedDTOs, inRepoID: repoID, reconcileOpen: false)
        }

        // Poll threads/CI for every open PR. When the open list 304'd we don't
        // have fresh DTOs, so fall back to the stored open set — inline comments
        // change without moving the list ETag, so per-PR polling must continue.
        let targets: [PRPollTarget]
        if let openDTOs {
            targets = openDTOs.map { PRPollTarget(nodeID: $0.node_id, number: $0.number, headSha: $0.head.sha) }
        } else {
            targets = await syncActor.openPRPollTargets(repoID: repoID)
        }

        // Each task reports whether all of its fetches succeeded, so the baseline
        // pass can tell whether it saw the repo's full current state.
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            let semaphore = AsyncSemaphore(value: 5)
            let actorRef = syncActor
            let clientRef = client
            for target in targets {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    do {
                        // nil == 304 Not Modified: keep stored data, skip upsert.
                        if !target.headSha.isEmpty,
                           let dto = try await clientRef.checkRuns(repo: ref, ref: target.headSha) {
                            try await actorRef.upsertCIChecks(prID: target.nodeID, dto: dto)
                        }
                        async let t = clientRef.timeline(repo: ref, number: target.number)
                        async let r = clientRef.reviews(repo: ref, number: target.number)
                        async let rc = clientRef.reviewComments(repo: ref, number: target.number)
                        let (tItems, reviewDTOs, reviewComments) = try await (t, r, rc)
                        if let tItems { try await actorRef.upsertTimeline(prID: target.nodeID, items: tItems) }
                        if let reviewDTOs { try await actorRef.upsertReviewerStates(prID: target.nodeID, fromReviews: reviewDTOs) }
                        if let reviewComments { try await actorRef.upsertReviewComments(prID: target.nodeID, fromDTOs: reviewComments) }
                        return true
                    } catch {
                        // Per-PR failure; toolbar surfaces aggregate errors only.
                        return false
                    }
                }
            }
            var all = true
            for await ok in group where !ok { all = false }
            return all
        }

        // Record the successful check even when every request 304'd, so the
        // per-repo "last checked" time reflects reality.
        if outcomes { try await syncActor.markRepoChecked(repoID: repoID, date: .now) }

        guard let d = notificationDispatcher else { return }
        if needsBaseline {
            // Only establish the baseline once we've seen the repo's full current
            // state — otherwise pre-existing comments that failed to fetch would
            // later notify as if new. On partial failure, stay unbaselined and
            // retry next cycle (silent until then). The baseline and the
            // "baselined" flag are written in one save so they can't diverge.
            if outcomes {
                await d.baselineRepoThreads(repoID: repoID)
            }
        } else {
            await d.process(repoID: repoID)
        }
    }

    // MARK: - Priority lane

    /// Register the PR currently open in the detail view and refresh it now.
    /// The priority loop then keeps it fresh on `priorityIntervalSec` until the
    /// selection changes or clears. Routing this through `SyncActor` (same as the
    /// whole-repo sync) is what keeps the list row and the open detail in sync.
    func selectPR(prID: String, ref: RepoRef, number: Int) {
        let sel = PrioritySelection(prID: prID, ref: ref, number: number)
        guard sel != prioritySelection else { return }
        prioritySelection = sel
        Task { [weak self] in await self?.refreshPR(sel) }
    }

    func clearPRSelection() {
        prioritySelection = nil
    }

    /// Manual "Refresh" button in the detail toolbar.
    func refreshSelectedPRNow() {
        guard let sel = prioritySelection else { return }
        Task { [weak self] in await self?.refreshPR(sel) }
    }

    private func priorityLoop() async {
        while !Task.isCancelled {
            if let sel = prioritySelection, !needsReauth { await refreshPR(sel) }
            try? await Task.sleep(nanoseconds: UInt64(priorityIntervalSec * 1_000_000_000))
        }
    }

    /// Fetch a single PR's threads/CI/detail and upsert them. Overlapping calls
    /// (the loop tick racing the immediate refresh on selection) are coalesced by
    /// the `isRefreshingDetail` guard — the upserts are idempotent, so skipping a
    /// duplicate in-flight pass loses nothing.
    private func refreshPR(_ sel: PrioritySelection) async {
        if isRefreshingDetail { return }
        isRefreshingDetail = true
        defer { isRefreshingDetail = false }

        // The head SHA moves as commits land, so read the current one from the
        // store each time rather than capturing it at selection.
        let ctx = ModelContext(modelContainer)
        let prID = sel.prID
        let headSha = (try? ctx.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.id == prID })))?.first?.headSha ?? ""
        let ref = sel.ref
        do {
            async let t = client.timeline(repo: ref, number: sel.number)
            async let r = client.reviews(repo: ref, number: sel.number)
            async let d = client.pullRequestDetail(repo: ref, number: sel.number)
            async let rc = client.reviewComments(repo: ref, number: sel.number)
            // nil == 304 Not Modified: keep the stored data, skip that upsert.
            let (tItems, reviewDTOs, detail, reviewComments) = try await (t, r, d, rc)
            if let tItems { try await syncActor.upsertTimeline(prID: prID, items: tItems) }
            if let reviewDTOs { try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs) }
            if let reviewComments { try await syncActor.upsertReviewComments(prID: prID, fromDTOs: reviewComments) }
            if let detail { try await syncActor.updatePRStatistics(prID: prID, dto: detail) }
            // Checks key off the head SHA, so fetch them after we have it.
            if !headSha.isEmpty, let checks = try await client.checkRuns(repo: ref, ref: headSha) {
                try await syncActor.upsertCIChecks(prID: prID, dto: checks)
            }
            try await syncActor.setLastFetched(prID: prID, date: .now)
            lastDetailError = nil
        } catch is CancellationError {
            // Selection moved on; the next task reloads. Don't surface.
        } catch let e as GitHubError {
            // Some networking layers wrap cancellation as a `.network` error.
            if case .network(let msg) = e, msg.lowercased().contains("cancel") { return }
            // A 401 here means the same dead token — hand it to the reauth
            // banner rather than the detail view's transient-error line.
            if e == .unauthorized { needsReauth = true } else { lastDetailError = e }
        } catch {
            if error.localizedDescription.lowercased().contains("cancel") { return }
            lastDetailError = .network(message: error.localizedDescription)
        }
    }

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            self?.isBackgroundMode = !win.occlusionState.contains(.visible)
        }
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.start()
        }
    }
}

extension SyncCoordinator {
    var clientForView: GitHubClient { client }
    var syncActorForView: SyncActor { syncActor }
    var modelContainerForView: ModelContainer { modelContainer }
}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if !waiters.isEmpty { waiters.removeFirst().resume() } else { value += 1 }
    }
}
