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
    @Query private var viewerStates: [ViewerState]
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .general

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            RepositoriesSettingsView(coordinator: coordinator)
                .tabItem { SwiftUI.Label("Repositories", systemImage: "folder") }
                .tag(SettingsTab.repositories)
            notificationsTab.tabItem { SwiftUI.Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            accountTab.tabItem { SwiftUI.Label("Account", systemImage: "person.circle") }
                .tag(SettingsTab.account)
        }
        .frame(width: 580, height: 400).padding(20)
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
        VStack(alignment: .leading, spacing: 14) {
            if let v = vs.viewer {
                HStack {
                    AvatarView(user: v, size: 32)
                    VStack(alignment: .leading) {
                        Text(v.name ?? v.login).font(.system(size: 14).weight(.semibold))
                        Text("@\(v.login)").microText().foregroundStyle(Tokens.textMuted)
                    }
                    Spacer()
                }
            } else {
                Text("Not signed in.").microText().foregroundStyle(Tokens.textMuted)
            }
            Button("Sign out") {
                keychain.delete()
                vs.viewer = nil
                try? ctx.save()
            }.foregroundStyle(Tokens.changes)
            Spacer()
        }
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
