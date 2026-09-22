import SwiftUI
import SwiftData
import ServiceManagement
import UserNotifications

/// Settings tab identity, persisted so callers (e.g. the sidebar's "Manage
/// repositories…") can deep-link the window to a specific tab.
enum SettingsTab: String {
    case general, repositories, notifications, account
    static let storageKey = "settingsSelectedTab"
}

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query private var viewerStates: [ViewerState]
    @Query(sort: [SortDescriptor(\Repo.id)]) private var repos: [Repo]
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .general

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    @State private var connectionResult: ConnectionCheckResult?
    @State private var isCheckingConnection = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            RepositoriesSettingsView(coordinator: coordinator, keychain: keychain)
                .tabItem { SwiftUI.Label("Repositories", systemImage: "folder") }
                .tag(SettingsTab.repositories)
            notificationsTab.tabItem { SwiftUI.Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            accountTab.tabItem { SwiftUI.Label("Account", systemImage: "person.circle") }
                .tag(SettingsTab.account)
        }
        .frame(width: 580, height: 400).padding(20)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                mode: repos.isEmpty ? .firstRun : .reconfigure,
                keychain: keychain,
                client: client,
                coordinator: coordinator)
                .modelContainer(coordinator.modelContainerForView)
                .interactiveDismissDisabled(repos.isEmpty)
        }
    }

    private var vs: ViewerState {
        if let existing = viewerStates.first { return existing }
        let new = ViewerState()
        ctx.insert(new)
        try? ctx.save()
        return new
    }

    @ViewBuilder private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Refresh interval: \(vs.refreshIntervalMinutes) min",
                value: Binding(get: { vs.refreshIntervalMinutes }, set: {
                    vs.refreshIntervalMinutes = $0
                    coordinator.setIntervals(foregroundMinutes: $0)
                    try? ctx.save()
                }), in: 1...10)
            Toggle("Launch at login", isOn: Binding(get: { vs.launchAtLoginEnabled }, set: { newValue in
                vs.launchAtLoginEnabled = newValue
                try? ctx.save()
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    // Best-effort: revert toggle if registration failed
                    vs.launchAtLoginEnabled = !newValue
                    try? ctx.save()
                }
            }))
            Picker("Theme", selection: Binding(
                get: { vs.themePreference },
                set: { newValue in
                    vs.themePreference = newValue
                    try? ctx.save()
                })) {
                Text("System").tag(ViewerState.ThemePreference.system)
                Text("Light").tag(ViewerState.ThemePreference.light)
                Text("Dark").tag(ViewerState.ThemePreference.dark)
            }
            .pickerStyle(.menu)
            Spacer()
        }
    }

    @ViewBuilder private var accountTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let v = vs.viewer {
                HStack {
                    AvatarView(user: v, size: 32)
                    VStack(alignment: .leading) {
                        Text(v.name ?? v.login).font(.system(size: 14).weight(.semibold))
                        Text("@\(v.login)").microText().foregroundStyle(Tokens.textMuted)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    accountMetaRow("Token type", tokenTypeLabel(vs.tokenType))
                    accountMetaRow("Scopes", vs.tokenScopes.isEmpty ? "None reported" : vs.tokenScopes.joined(separator: ", "))
                    accountMetaRow("Expires", vs.tokenExpirationDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "No expiration reported")
                }

                Divider()
                if coordinator.needsReauth {
                    HStack {
                        Text("GitHub needs you to reconnect.").microText().foregroundStyle(Tokens.changes)
                        Spacer()
                        Button("Reconnect") { showOnboarding = true }
                    }
                }
                if let connectionResult {
                    if let problem = connectionResult.items.first(where: { $0.status == .failure && !$0.id.hasPrefix("repo:") }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(problem.title).font(.system(size: 11, weight: .semibold))
                            Text(problem.message).font(.system(size: 11)).foregroundStyle(Tokens.changes)
                            if let action = problem.action {
                                Button(action.label) { openURL(action.url) }
                                    .font(.system(size: 11, weight: .medium))
                                    .buttonStyle(.link)
                            }
                        }
                    }
                    ForEach(repoHealth) { health in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: health.status == .failure ? "xmark.circle.fill" : health.status == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(health.status == .failure ? Tokens.changes : health.status == .warning ? Tokens.pending : Tokens.approved)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(health.repo.id).font(.system(size: 12, weight: .medium))
                                Text(health.reason).font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                                if let action = health.action {
                                    Button(action.label) { openURL(action.url) }
                                        .font(.system(size: 11, weight: .medium))
                                        .buttonStyle(.link)
                                }
                            }
                            Spacer()
                        }
                    }
                    if repos.isEmpty {
                        Text("No repositories configured.").microText().foregroundStyle(Tokens.textMuted)
                    }
                    Button {
                        Task { await checkConnection() }
                    } label: {
                        if isCheckingConnection { ProgressView().controlSize(.small) } else { Text("Check again") }
                    }
                    .disabled(isCheckingConnection)
                } else {
                    Text("Check the connection to see repository access.").microText().foregroundStyle(Tokens.textMuted)
                    Button("Check again") { Task { await checkConnection() } }
                }
            } else {
                Text("Not signed in.").microText().foregroundStyle(Tokens.textMuted)
                Button("Sign in / Reconnect") { showOnboarding = true }
            }

            if vs.viewer != nil {
                Button("Sign out") {
                    coordinator.signOut()
                    keychain.delete()
                    vs.viewer = nil
                    vs.tokenType = nil
                    vs.tokenScopes = []
                    vs.tokenExpirationDate = nil
                    connectionResult = nil
                    try? ctx.save()
                }.foregroundStyle(Tokens.changes)
            }
            Spacer()
        }
        .task { await checkConnection() }
    }

    private struct RepoHealth: Identifiable {
        let repo: Repo
        let status: ConnectionCheckStatus
        let reason: String
        let action: GitHubErrorAction?
        var id: String { repo.id }
    }

    private var repoHealth: [RepoHealth] {
        repos.filter(\.isEnabled).map { repo in
            let items = connectionResult?.items.filter { $0.id.hasPrefix("repo:\(repo.id):") } ?? []
            let failures = items.filter { $0.status == .failure }
            let warnings = items.filter { $0.status == .warning }
            let status: ConnectionCheckStatus = !failures.isEmpty ? .failure : !warnings.isEmpty ? .warning : .ok
            let reason = (failures + warnings).map(\.message).joined(separator: " ")
            return RepoHealth(repo: repo, status: status, reason: reason.isEmpty ? "All required access is available." : reason, action: (failures + warnings).compactMap(\.action).first)
        }
    }

    private func accountMetaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            Spacer()
            Text(value).font(.system(size: 11)).foregroundStyle(Tokens.text)
        }
    }

    private func tokenTypeLabel(_ type: GitHubTokenType?) -> String {
        switch type {
        case .classic: return "Classic personal access token"
        case .fineGrained: return "Fine-grained personal access token"
        case .other: return "Personal access token"
        case nil: return "Unknown"
        }
    }

    private func checkConnection() async {
        guard let token = keychain.load(), !token.isEmpty else {
            connectionResult = nil
            return
        }
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        let refs = repos.filter(\.isEnabled).map { RepoRef(owner: $0.owner, name: $0.name) }
        let result = await ConnectionCheck(client: client, token: token).run(repos: refs)
        connectionResult = result
        if case .unauthorized = result.identityError {
            coordinator.needsReauth = true
        }
        if let dto = result.viewer {
            let user = vs.viewer ?? User(login: dto.login)
            user.name = dto.name
            user.avatarURL = dto.avatar_url
            if vs.viewer == nil { ctx.insert(user) }
            vs.viewer = user
        }
        vs.tokenType = result.metadata.type
        vs.tokenScopes = result.metadata.scopes
        vs.tokenExpirationDate = result.metadata.expiration
        try? ctx.save()
    }

    @ViewBuilder private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Badging").font(.headline)
            Text("Notification preferences are configured per repository in the Repositories tab.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.textFaint)
            Toggle("Show indicator on menu-bar icon", isOn: Binding(
                get: { vs.menuBarBadgeEnabled },
                set: { newValue in
                    vs.menuBarBadgeEnabled = newValue
                    try? ctx.save()
                    coordinator.badgeController?.menuBarEnabled = newValue
                    coordinator.badgeController?.apply()
                }))
            Toggle("Show indicator on Dock icon", isOn: Binding(
                get: { vs.dockBadgeEnabled },
                set: { newValue in
                    vs.dockBadgeEnabled = newValue
                    try? ctx.save()
                    coordinator.badgeController?.dockEnabled = newValue
                    coordinator.badgeController?.apply()
                }))

            Spacer()
        }
    }
}
