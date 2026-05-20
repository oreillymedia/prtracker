import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    @State private var newRepo: String = ""

    var body: some View {
        TabView {
            generalTab.tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
            accountTab.tabItem { SwiftUI.Label("Account", systemImage: "person.circle") }
            repoTab.tabItem    { SwiftUI.Label("Repository", systemImage: "folder") }
        }
        .frame(width: 480, height: 280).padding(20)
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

    @ViewBuilder private var repoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active repository: \(vs.activeRepoID ?? "—")")
            HStack {
                TextField("owner/name", text: $newRepo).textFieldStyle(.roundedBorder)
                Button("Switch") { switchRepo() }.disabled(!newRepo.contains("/"))
            }
            Spacer()
        }
    }

    private func switchRepo() {
        let parts = newRepo.split(separator: "/")
        guard parts.count == 2 else { return }
        let owner = String(parts[0]); let name = String(parts[1])
        let id = "\(owner)/\(name)"
        let existing = (try? ctx.fetch(FetchDescriptor<Repo>())) ?? []
        for r in existing { r.isActive = false }
        if let already = existing.first(where: { $0.id == id }) {
            already.isActive = true
            vs.activeRepoID = already.id
        } else {
            let r = Repo(owner: owner, name: name, isActive: true)
            ctx.insert(r)
            vs.activeRepoID = r.id
        }
        try? ctx.save()
        newRepo = ""
        Task { await coordinator.refresh() }
    }
}
