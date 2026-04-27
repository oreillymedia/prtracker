import Foundation
import SwiftData
import AppKit

@Observable
final class SyncCoordinator {
    private let client: GitHubClient
    private let syncActor: SyncActor
    private let modelContainer: ModelContainer

    var isSyncing: Bool = false
    var lastSyncAt: Date?
    var lastSyncError: GitHubError?

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
        guard let active = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isActive == true })))?.first else {
            return
        }
        let ref = RepoRef(owner: active.owner, name: active.name)
        let repoID = active.id

        do {
            async let openPRs = client.listOpenPRs(repo: ref)
            async let recent = client.listRecentlyMerged(repo: ref, limit: 20)
            async let notifs = client.participatingNotifications()
            let (open, closed, _) = try await (openPRs, recent, notifs)
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

            lastSyncAt = .now
        } catch let e as GitHubError {
            lastSyncError = e
        } catch {
            lastSyncError = .network(message: error.localizedDescription)
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
