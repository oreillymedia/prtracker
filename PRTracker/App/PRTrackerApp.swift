import SwiftUI
import SwiftData
import Sparkle
import UserNotifications

@main
struct PRTrackerApp: App {
    let container: ModelContainer
    let appState: AppState
    let keychain: Keychain
    let client: GitHubClient
    let syncActor: SyncActor
    let coordinator: SyncCoordinator
    let badgeController: BadgeController
    let notificationDelegate: NotificationDelegate
    let dispatcher: NotificationDispatcher
    @State private var updater = Updater()

    init() {
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
            ReviewComment.self, NotificationLog.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let c = Self.makeContainer(schema: schema, configuration: cfg)
        let bc = BadgeController()
        let bootCtx = ModelContext(c)
        if let vs = (try? bootCtx.fetch(FetchDescriptor<ViewerState>()))?.first {
            bc.menuBarEnabled = vs.menuBarBadgeEnabled
            bc.dockEnabled = vs.dockBadgeEnabled
        }
        let kc = Keychain()
        let cli = GitHubClient(
            session: URLSession(configuration: .default),
            tokenProvider: { kc.load() })
        let act = SyncActor(modelContainer: c)
        self.container = c
        self.appState = AppState()
        self.keychain = kc
        self.client = cli
        self.syncActor = act
        self.badgeController = bc
        self.coordinator = SyncCoordinator(client: cli, syncActor: act, modelContainer: c)

        let d = NotificationDispatcher(modelContainer: c, poster: UNCenterPoster())
        let delegate = NotificationDelegate()
        delegate.appState = self.appState
        UNUserNotificationCenter.current().delegate = delegate
        self.notificationDelegate = delegate
        self.dispatcher = d
        self.coordinator.notificationDispatcher = d
        self.coordinator.badgeController = self.badgeController
    }

    /// Open the on-disk store, recovering from an unmigratable schema as a last
    /// resort. Destroying the store is only acceptable for a genuinely
    /// incompatible store (we don't handle migrations yet) — NOT for a transient
    /// failure (file lock, sandbox hiccup, disk pressure). So we retry once
    /// before wiping: a deterministic schema mismatch fails again and triggers
    /// the rebuild, while a transient error usually clears on the retry and the
    /// user's data is preserved.
    private static func makeContainer(schema: Schema, configuration cfg: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [cfg])
        } catch {
            // Second attempt absorbs transient open failures without data loss.
            if let container = try? ModelContainer(for: schema, configurations: [cfg]) {
                return container
            }
            // Still failing — treat the store as incompatible and rebuild it.
            deleteStore(at: cfg.url)
            return try! ModelContainer(for: schema, configurations: [cfg])
        }
    }

    /// Remove a SQLite store and its sidecar files. Sibling names are derived
    /// from the store's actual filename (not an assumed extension), so a custom
    /// ModelConfiguration URL is handled correctly.
    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        for name in [base, base + "-wal", base + "-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(keychain: keychain, client: client, coordinator: coordinator)
                .environment(appState)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                Button("Set Up PR Tracker Again…") {
                    appState.showReconfigure = true
                }
            }
        }

//        MenuBarExtra {
//            MenuBarContentView(coordinator: coordinator, controller: badgeController)
//                .environment(appState)
//                .modelContainer(container)
//        } label: {
//            MenuBarLabel(controller: badgeController)
//        }
//        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(keychain: keychain, client: client, coordinator: coordinator)
                .modelContainer(container)
                .environment(appState)
        }
    }
}
