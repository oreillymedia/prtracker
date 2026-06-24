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

        guard viewerStates.first != nil else { return }
        // Only prompt if at least one repo actually wants notifications.
        if repos.allSatisfy({ $0.notificationLevel == .none }) { return }

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
        // The app always shows MainView; onboarding is a sheet MainView presents
        // automatically when no repos are configured (or on demand to reconfigure).
        MainView(keychain: keychain, client: client, coordinator: coordinator, onOpenSettings: { openSettings() })
            .task {
                // Apply the persisted refresh cadence before starting the loop;
                // otherwise the loop runs at the hardcoded default until the user
                // re-touches the Settings stepper.
                if let minutes = viewerStates.first?.refreshIntervalMinutes {
                    coordinator.setIntervals(foregroundMinutes: minutes)
                }
                coordinator.start()
                await firstLaunchAuthorizationIfNeeded()
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
    // Enabled-repo PRs only. Filtering at the fetch excludes a repo's PRs the
    // moment it's disabled or cascade-deleted, so the detail lookup never
    // dereferences a dangling `repo` relationship on a deleted PR.
    @Query(filter: #Predicate<PullRequest> { $0.repo.isEnabled }) private var prs: [PullRequest]
    @Query private var repos: [Repo]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    @State private var showOnboarding = false
    @State private var onboardingMode: OnboardingModel.Mode = .firstRun

    var body: some View {
        @Bindable var appState = appState
        let viewer = viewerStates.first?.viewer

        NavigationSplitView {
            MailSourceColumn(coordinator: coordinator, onOpenSettings: onOpenSettings)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, syncActor: coordinator.syncActorForView, dispatcher: coordinator.notificationDispatcher)
            } else {
                MailEmptyDetailView()
            }
        }
        // First-run onboarding presents automatically when no repos are
        // configured; the menu command requests a reconfigure (only meaningful
        // once at least one repo exists).
        .onAppear { if repos.isEmpty { presentOnboarding(.firstRun) } }
        .onChange(of: repos.isEmpty) { _, isEmpty in
            if isEmpty { presentOnboarding(.firstRun) }
        }
        .onChange(of: appState.showReconfigure) { _, on in
            guard on else { return }
            if repos.isEmpty {
                appState.showReconfigure = false   // nothing to reconfigure yet
            } else {
                presentOnboarding(.reconfigure)
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { appState.showReconfigure = false }) {
            OnboardingView(mode: onboardingMode, keychain: keychain, client: client, coordinator: coordinator)
                // The sheet doesn't inherit the window's SwiftData container, so
                // re-inject it (same as the Settings scene). Without this,
                // OnboardingView's @Environment(\.modelContext) is a throwaway
                // empty store: seed() can't pre-fill and commit() can't persist.
                .modelContainer(coordinator.modelContainerForView)
                .interactiveDismissDisabled(onboardingMode == .firstRun)
        }
    }

    private func presentOnboarding(_ mode: OnboardingModel.Mode) {
        onboardingMode = mode
        showOnboarding = true
    }
}
