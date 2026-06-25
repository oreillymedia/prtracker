import Foundation
import SwiftData
import AppKit

@Observable
final class SyncCoordinator {
    let client: GitHubClient
    let syncActor: SyncActor
    private let modelContainer: ModelContainer

    var isSyncing: Bool = false
    var lastSyncAt: Date?
    var lastSyncError: GitHubError?
    var notificationDispatcher: NotificationDispatcher?
    var badgeController: BadgeController?

    private var task: Task<Void, Never>?
    private var foregroundIntervalSec: TimeInterval = 120
    private var backgroundIntervalSec: TimeInterval = 300
    private var isBackgroundMode = false
    /// Set when a refresh is requested while one is already running, so the
    /// in-flight pass is followed by one more instead of being silently dropped.
    private var pendingRefresh = false

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
    }

    func stop() {
        task?.cancel(); task = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await refresh()
            let interval = isBackgroundMode ? backgroundIntervalSec : foregroundIntervalSec
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func refresh() async {
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

        var anySucceeded = false
        for repo in enabled {
            let ref = RepoRef(owner: repo.owner, name: repo.name)
            // A repo needs a silent baseline (record current state without
            // posting) until its threads have been fetched and baselined once —
            // covers a never-synced repo AND the first run after thread polling
            // was added to existing installs. Both avoid a backlog flood.
            let needsBaseline = repo.lastFetchedAt == nil || !repo.didBaselineThreads
            do {
                try await refreshRepo(ref: ref, repoID: repo.id, needsBaseline: needsBaseline)
                anySucceeded = true
            } catch let e as GitHubError {
                lastSyncError = e
            } catch {
                lastSyncError = .network(message: error.localizedDescription)
            }
        }
        if anySucceeded { lastSyncAt = .now }
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
        async let openPRs = client.listOpenPRs(repo: ref)
        async let recent = client.listRecentlyMerged(repo: ref, limit: 20)
        let (open, closed) = try await (openPRs, recent)
        let allPRs = open + closed
        try await syncActor.upsertPullRequests(allPRs, inRepoID: repoID)

        // Each task reports whether all of its fetches succeeded, so the baseline
        // pass can tell whether it saw the repo's full current state.
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            let semaphore = AsyncSemaphore(value: 5)
            let actorRef = syncActor
            let clientRef = client
            for pr in open {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    do {
                        // nil == 304 Not Modified: keep stored data, skip upsert.
                        if let dto = try await clientRef.checkRuns(repo: ref, ref: pr.head.sha) {
                            try await actorRef.upsertCIChecks(prID: pr.node_id, dto: dto)
                        }
                        async let t = clientRef.timeline(repo: ref, number: pr.number)
                        async let r = clientRef.reviews(repo: ref, number: pr.number)
                        async let rc = clientRef.reviewComments(repo: ref, number: pr.number)
                        let (tItems, reviewDTOs, reviewComments) = try await (t, r, rc)
                        if let tItems { try await actorRef.upsertTimeline(prID: pr.node_id, items: tItems) }
                        if let reviewDTOs { try await actorRef.upsertReviewerStates(prID: pr.node_id, fromReviews: reviewDTOs) }
                        if let reviewComments { try await actorRef.upsertReviewComments(prID: pr.node_id, fromDTOs: reviewComments) }
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
