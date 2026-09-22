import SwiftUI
import SwiftData

/// Lightweight re-authentication shown when the stored token expires or is
/// revoked (a GitHub 401). Just a token field and a validate button — far
/// lighter than re-running the full onboarding to swap a single credential.
/// On success it saves the new token, tells the coordinator to resume syncing,
/// and dismisses. The viewer identity is intentionally left untouched:
/// reconnecting renews the token for the same account, while switching accounts
/// is a reconfigure-level action handled by onboarding.
struct ReconnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorText: String?
    @State private var problem: GitHubErrorPresentation?

    private var trimmed: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canValidate: Bool { !trimmed.isEmpty && !isValidating }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reconnect to GitHub").font(.system(size: 15, weight: .semibold))
                Text("Your access token expired or was revoked. Paste a new token with repo access to resume syncing.")
                    .font(.system(size: 12)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(GitHubTokenGuide.checklist.enumerated()), id: \.offset) { index, item in
                        SwiftUI.Label(item, systemImage: "\(index + 1).circle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Tokens.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            SecureField("ghp_… or github_pat_…", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canValidate { Task { await validate() } } }
            if let problem {
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.title).font(.system(size: 11, weight: .semibold))
                    Text(problem.detail).font(.system(size: 11))
                    if let action = problem.action {
                        Button(action.label) { openURL(action.url) }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.link)
                    }
                }
                .foregroundStyle(Tokens.changes)
            }
            HStack {
                Link("Create a token…", destination: GitHubTokenGuide.tokenURL).font(.system(size: 11))
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    Task { await validate() }
                } label: {
                    if isValidating { ProgressView().controlSize(.small) } else { Text("Reconnect") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canValidate)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func validate() async {
        isValidating = true; defer { isValidating = false }
        errorText = nil
        problem = nil
        keychain.save(trimmed)
        let ctx = ModelContext(coordinator.modelContainerForView)
        let repos = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isEnabled == true }))) ?? []
        let refs = repos.map { RepoRef(owner: $0.owner, name: $0.name) }
        let result = await ConnectionCheck(client: client, token: trimmed).run(repos: refs)

        if let failure = result.items.first(where: { $0.status == .failure }) {
            problem = GitHubErrorPresentation(title: failure.title, detail: failure.message, action: failure.action)
            errorText = failure.message
            if case .network = result.identityError { return }
            if case .decoding = result.identityError { return }
            keychain.delete()
            return
        }

        persist(result, in: ctx)
        coordinator.reconnected()
        dismiss()
    }

    private func persist(_ result: ConnectionCheckResult, in ctx: ModelContext) {
        guard let dto = result.viewer else { return }
        let state = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first ?? {
            let value = ViewerState()
            ctx.insert(value)
            return value
        }()
        let user = state.viewer ?? User(login: dto.login)
        user.name = dto.name
        user.avatarURL = dto.avatar_url
        if state.viewer == nil { ctx.insert(user) }
        state.viewer = user
        state.tokenType = result.metadata.type
        state.tokenScopes = result.metadata.scopes
        state.tokenExpirationDate = result.metadata.expiration
        try? ctx.save()
    }
}
