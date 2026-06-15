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

    /// Open the on-disk store, recovering from an unmigratable schema. If the
    /// container can't be created (e.g. an older store whose schema SwiftData
    /// can't lightweight-migrate), delete the store files and start fresh —
    /// acceptable here since all data is re-fetched from GitHub on next sync.
    private static func makeContainer(schema: Schema, configuration cfg: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [cfg])
        } catch {
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                let url = cfg.url.deletingPathExtension().appendingPathExtension("store\(suffix)")
                try? fm.removeItem(at: url)
            }
            try? fm.removeItem(at: cfg.url)
            return try! ModelContainer(for: schema, configurations: [cfg])
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
