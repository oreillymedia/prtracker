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
    private var backgroundIntervalSec: TimeInterval = 600
    private var isBackgroundMode = false

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
        if isSyncing { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let ctx = ModelContext(modelContainer)
        let enabled = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isEnabled == true }))) ?? []
        if enabled.isEmpty { return }

        var anySucceeded = false
        for repo in enabled {
            let ref = RepoRef(owner: repo.owner, name: repo.name)
            // A repo's very first successful sync establishes a silent baseline
            // instead of posting — its whole current state is pre-existing, not
            // new activity. `lastFetchedAt == nil` marks a never-synced repo
            // (set by upsertPullRequests on success), covering newly-added and
            // freshly-onboarded repos without a per-call flag.
            let isFirstSync = repo.lastFetchedAt == nil
            do {
                try await refreshRepo(ref: ref, repoID: repo.id, isFirstSync: isFirstSync)
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
    /// refresh CI checks for open PRs, then run notifications for the repo. A
    /// thrown error aborts only this repo; `refresh()` continues to the next.
    private func refreshRepo(ref: RepoRef, repoID: String, isFirstSync: Bool) async throws {
        async let openPRs = client.listOpenPRs(repo: ref)
        async let recent = client.listRecentlyMerged(repo: ref, limit: 20)
        let (open, closed) = try await (openPRs, recent)
        let allPRs = open + closed
        try await syncActor.upsertPullRequests(allPRs, inRepoID: repoID)

        await withTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore(value: 5)
            let actorRef = syncActor
            let clientRef = client
            for pr in open {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    do {
                        let dto = try await clientRef.checkRuns(repo: ref, ref: pr.head.sha)
                        try await actorRef.upsertCIChecks(prID: pr.node_id, dto: dto)
                    } catch is GitHubError {
                        // ignore per-PR failures; toolbar surfaces aggregate errors only
                    } catch { }
                }
            }
        }

        if let d = notificationDispatcher {
            if isFirstSync {
                // Silently record everything currently present so only later
                // activity notifies; avoids a backlog flood on a new repo.
                await d.backfillSilentBaseline(repoID: repoID)
            } else {
                await d.process(repoID: repoID)
            }
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
