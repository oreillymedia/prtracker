import SwiftUI
import SwiftData
import Sparkle

@main
struct PRTrackerApp: App {
    let container: ModelContainer
    let appState: AppState
    let keychain: Keychain
    let client: GitHubClient
    let syncActor: SyncActor
    let coordinator: SyncCoordinator
    let badge = MenuBarBadge()
    @State private var updater = Updater()

    init() {
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
            ReviewComment.self, NotificationLog.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let c = try! ModelContainer(for: schema, configurations: [cfg])
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
        self.coordinator = SyncCoordinator(client: cli, syncActor: act, modelContainer: c)
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

        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator, badge: badge)
                .environment(appState)
                .modelContainer(container)
        } label: {
            MenuBarLabel(badge: badge)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(keychain: keychain, client: client, coordinator: coordinator)
                .modelContainer(container)
                .environment(appState)
        }
    }
}
