import SwiftUI
import SwiftData
import UserNotifications

/// Mail-Accounts–style master-detail for managing tracked repositories: a left
/// list with +/− controls, and a detail panel holding the selected repo's
/// enable toggle and per-repo notification level.
struct RepositoriesSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.controlActiveState) private var controlActiveState
    @Query(sort: [SortDescriptor(\Repo.id)]) private var repos: [Repo]

    let coordinator: SyncCoordinator

    @State private var selectedRepoID: String?
    @State private var showAddSheet = false
    @State private var newRepo = ""
    @State private var repoPendingDeletion: Repo?
    @State private var authDeniedHintVisible = false

    private var selectedRepo: Repo? { repos.first { $0.id == selectedRepoID } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedRepoID) {
                    ForEach(repos) { repo in
                        repoRow(repo).tag(repo.id)
                    }
                }
                .listStyle(.inset)
                Divider()
                addRemoveBar
            }
            .frame(width: 200)

            Divider()

            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selectedRepoID == nil { selectedRepoID = repos.first?.id } }
        .sheet(isPresented: $showAddSheet) { addSheet }
        .confirmationDialog(
            "Delete \(repoPendingDeletion?.id ?? "")?",
            isPresented: Binding(get: { repoPendingDeletion != nil }, set: { if !$0 { repoPendingDeletion = nil } }),
            presenting: repoPendingDeletion) { repo in
            Button("Delete", role: .destructive) { deleteRepo(repo) }
            Button("Cancel", role: .cancel) { repoPendingDeletion = nil }
        } message: { _ in
            Text("This removes the repository and all of its stored pull requests. This can't be undone.")
        }
    }

    // MARK: - Left list

    private func repoRow(_ repo: Repo) -> some View {
        // White text on the system selection fill; dark otherwise. Mirrors
        // MailRowView's `highlighted` treatment for legibility.
        let highlighted = (repo.id == selectedRepoID) && controlActiveState != .inactive
        return VStack(alignment: .leading, spacing: 1) {
            Text(repo.name).font(.system(size: 12, weight: .medium))
                .foregroundStyle(highlighted ? Color.white : Tokens.text).lineLimit(1)
            Text(repo.isEnabled ? repo.owner : "Disabled")
                .font(.system(size: 10.5))
                .foregroundStyle(highlighted ? Color.white.opacity(0.85) : Tokens.textMuted).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var addRemoveBar: some View {
        HStack(spacing: 0) {
            Button { newRepo = ""; showAddSheet = true } label: {
                Image(systemName: "plus").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Add a repository")
            Divider().frame(height: 14)
            Button { if let r = selectedRepo { repoPendingDeletion = r } } label: {
                Image(systemName: "minus").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(selectedRepo == nil)
            .help("Remove the selected repository")
            Spacer()
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
    }

    // MARK: - Detail panel

    @ViewBuilder private var detailPanel: some View {
        if let repo = selectedRepo {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable this repository", isOn: Binding(
                        get: { repo.isEnabled },
                        set: { newValue in
                            repo.isEnabled = newValue
                            try? ctx.save()
                            if newValue { Task { await coordinator.refresh() } }
                        }))

                    VStack(alignment: .leading, spacing: 4) {
                        metaRow("Repository", repo.id)
                        metaRow("Last synced", repo.lastFetchedAt.map { RelativeTimeFormatter.short($0) } ?? "Never")
                    }

                    Divider()

                    Text("Notify me about").font(.headline)
                    Picker("", selection: Binding(
                        get: { repo.notificationLevel },
                        set: { newValue in
                            let previous = repo.notificationLevel
                            repo.notificationLevel = newValue
                            try? ctx.save()
                            Task { await handleLevelChange(repo: repo, previous: previous, newValue: newValue) }
                        })) {
                        Text("Everything — all comments, reviews, CI failures, commits, and state changes").tag(NotificationLevel.everything)
                        Text("Personal — PRs you authored, replies to your comments").tag(NotificationLevel.personal)
                        Text("None — no notifications").tag(NotificationLevel.none)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    if authDeniedHintVisible {
                        Text("macOS notifications are disabled for PR Tracker. Enable in System Settings → Notifications → PR Tracker.")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.textFaint)
                    }

                    Spacer()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: repo.id) { await refreshAuthHint(repo: repo) }
        } else {
            VStack {
                Spacer()
                Text(repos.isEmpty ? "Add a repository with the + button." : "Select a repository.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            Spacer()
            Text(value).font(.system(size: 11)).foregroundStyle(Tokens.text)
        }
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Repository").font(.headline)
            TextField("owner/name", text: $newRepo)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") { showAddSheet = false }
                Button("Add") { addRepo() }.disabled(!canAddRepo).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Actions

    /// Add is allowed only for a well-formed "owner/name" that isn't already tracked.
    private var canAddRepo: Bool {
        guard let ref = RepoRef.parse(newRepo) else { return false }
        return !repos.contains { $0.id == ref.slug }
    }

    private func addRepo() {
        guard let ref = RepoRef.parse(newRepo), !repos.contains(where: { $0.id == ref.slug }) else { return }
        ctx.insert(Repo(owner: ref.owner, name: ref.name))
        try? ctx.save()
        newRepo = ""
        showAddSheet = false
        selectedRepoID = ref.slug
        Task { await coordinator.refresh() }
    }

    private func deleteRepo(_ repo: Repo) {
        let wasSelected = (selectedRepoID == repo.id)
        let deletedID = repo.id
        ctx.delete(repo)
        try? ctx.save()
        repoPendingDeletion = nil
        if wasSelected { selectedRepoID = repos.first(where: { $0.id != deletedID })?.id }
    }

    private func handleLevelChange(repo: Repo, previous: NotificationLevel, newValue: NotificationLevel) async {
        if newValue == .none {
            authDeniedHintVisible = false
            return
        }
        let auth = NotificationAuthorization()
        var status = await auth.currentStatus()
        if status == .notDetermined {
            status = await auth.requestAuthorization()
        }
        if status == .authorized && previous == .none {
            await coordinator.notificationDispatcher?.backfillSilentBaseline(repoID: repo.id)
        }
        authDeniedHintVisible = (status == .denied)
    }

    private func refreshAuthHint(repo: Repo) async {
        let status = await NotificationAuthorization().currentStatus()
        authDeniedHintVisible = (repo.notificationLevel != .none && status == .denied)
    }
}
