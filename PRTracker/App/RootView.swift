import SwiftUI
import SwiftData
import UserNotifications

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]

    @State private var lastActiveTriggerAt: Date = .distantPast
    @State private var didRunFirstLaunchAuth: Bool = false

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    private func resolvedColorScheme() -> ColorScheme? {
        switch viewerStates.first?.themePreference ?? .system {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    private func firstLaunchAuthorizationIfNeeded() async {
        if didRunFirstLaunchAuth { return }
        didRunFirstLaunchAuth = true

        guard let vs = viewerStates.first else { return }
        if vs.notificationLevel == .none { return }

        let auth = NotificationAuthorization()
        var status = await auth.currentStatus()
        if status == .notDetermined {
            status = await auth.requestAuthorization()
        }
        guard status == .authorized else { return }

        let logCount = (try? ctx.fetch(FetchDescriptor<NotificationLog>()))?.count ?? 0
        if logCount == 0 {
            await coordinator.notificationDispatcher?.backfillSilentBaseline()
        }
    }

    var body: some View {
        let signedIn = (keychain.load() != nil) && (viewerStates.first?.viewer != nil) && !repos.isEmpty
        Group {
            if signedIn {
                MainView(coordinator: coordinator, onOpenSettings: { openSettings() })
                    .task {
                        coordinator.start()
                        await firstLaunchAuthorizationIfNeeded()
                    }
            } else {
                OnboardingView(keychain: keychain, client: client, onReady: {
                    coordinator.start()
                })
            }
        }
        .preferredColorScheme(resolvedColorScheme())
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let now = Date.now
                if now.timeIntervalSince(lastActiveTriggerAt) > 30 {
                    lastActiveTriggerAt = now
                    Task { await coordinator.refresh() }
                }
            }
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query private var prs: [PullRequest]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        let viewer = viewerStates.first?.viewer

        NavigationSplitView {
            MailSourceColumn(coordinator: coordinator, onOpenSettings: onOpenSettings)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID && $0.repo.isEnabled }) {
                PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, syncActor: coordinator.syncActorForView)
            } else {
                MailEmptyDetailView()
            }
        }
    }
}
