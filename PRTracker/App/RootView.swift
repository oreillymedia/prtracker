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
                // Fill in derived activity times for rows migrated from before the
                // field existed, so list ordering is correct on the very first frame.
                try? await coordinator.syncActorForView.backfillActivityIfNeeded()
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
    @State private var showReconnect = false

    var body: some View {
        @Bindable var appState = appState
        let viewer = viewerStates.first?.viewer

        VStack(spacing: 0) {
            if coordinator.needsReauth { reauthBanner }
            NavigationSplitView {
                MailSourceColumn(coordinator: coordinator, onOpenSettings: onOpenSettings)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            } detail: {
                if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                    PRDetailView(pr: pr, viewer: viewer, coordinator: coordinator, syncActor: coordinator.syncActorForView)
                } else {
                    MailEmptyDetailView()
                }
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
            // Always open setup: first-run when nothing is configured yet (so a
            // cancelled first-run is reachable again), reconfigure otherwise.
            presentOnboarding(repos.isEmpty ? .firstRun : .reconfigure)
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
        .sheet(isPresented: $showReconnect) {
            ReconnectSheet(keychain: keychain, client: client, coordinator: coordinator)
        }
    }

    /// Full-width banner shown when the stored token is dead. Syncing is paused
    /// until the user pastes a working token via the Reconnect sheet.
    private var reauthBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("GitHub sync paused").font(.system(size: 12, weight: .semibold))
                Text("Your access token expired or was revoked.").font(.system(size: 11)).opacity(0.9)
            }
            Spacer()
            Button("Reconnect") { showReconnect = true }
                .controlSize(.small)
                .tint(.white)
                .foregroundStyle(Tokens.changes)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Tokens.changes)
    }

    private func presentOnboarding(_ mode: OnboardingModel.Mode) {
        onboardingMode = mode
        showOnboarding = true
    }
}
