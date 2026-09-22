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
        // Save first: the client reads the token from the keychain per request,
        // so validate() below exercises exactly the credential we're storing.
        keychain.save(trimmed)
        do {
            _ = try await client.validateWithMetadata()
            // /user only proves the token authenticates. Verify it can actually
            // reach the configured repos too — GitHub returns 404 for a private
            // repo a token can't see, which would otherwise clear the banner and
            // then resurface as a confusing "repoNotFound" on every load.
            if let blocked = try await firstInaccessibleRepo() {
                keychain.delete()
                errorText = "That token can't access \(blocked). Give it access to that repository and try again."
                return
            }
            coordinator.reconnected()
            dismiss()
        } catch let error as GitHubError {
            problem = error.userFacing
            errorText = error.userFacing.detail
            if case .network = error { return }
            if case .decoding = error { return }
            keychain.delete()
        } catch {
            problem = GitHubError.network(message: error.localizedDescription).userFacing
            errorText = "Couldn't reach GitHub. Check your connection and try again."
        }
    }

    /// Slug of the first enabled repo the just-entered token can't reach, or nil
    /// if all are accessible. Only GitHub's access signals (404/401) count as
    /// inaccessible; a transient network error propagates to the generic catch.
    private func firstInaccessibleRepo() async throws -> String? {
        let ctx = ModelContext(coordinator.modelContainerForView)
        let repos = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isEnabled == true }))) ?? []
        for repo in repos {
            do {
                _ = try await client.repository(RepoRef(owner: repo.owner, name: repo.name))
            } catch let e as GitHubError where e == .repoNotFound || e == .unauthorized || e == .forbidden {
                return "\(repo.owner)/\(repo.name)"
            }
        }
        return nil
    }
}
