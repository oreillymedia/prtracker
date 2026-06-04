import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var ctx
    @State private var token: String = ""
    @State private var ownerRepo: String = ""
    @State private var error: String?
    @State private var isValidating = false
    @State private var stage: Stage = .token

    enum Stage { case token, repo }

    let keychain: Keychain
    let client: GitHubClient
    var onReady: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up PR Tracker")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tokens.text)

            VStack(alignment: .leading, spacing: 12) {
                switch stage {
                case .token:
                    Text("Paste a GitHub Personal Access Token (classic or fine-grained) with `repo` scope.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Tokens.textMuted)
                    SecureField("ghp_…", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 420)
                    Button("Validate") { Task { await validateToken() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(token.isEmpty || isValidating)
                case .repo:
                    Text("Which repository do you want to track?")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Tokens.textMuted)
                    TextField("owner/name", text: $ownerRepo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 420)
                    Button("Save") { Task { await saveRepo() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(!ownerRepo.contains("/") || isValidating)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.changes)
                }
            }
            .padding(16)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(28)
        .frame(width: 520, height: 320)
    }

    private func validateToken() async {
        isValidating = true; defer { isValidating = false }
        keychain.save(token)
        do {
            let user = try await client.validate()
            let existingVS = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first
            let vs: ViewerState
            if let existingVS {
                vs = existingVS
            } else {
                let new = ViewerState(); ctx.insert(new); vs = new
            }
            let u = User(login: user.login, name: user.name, avatarURL: user.avatar_url)
            ctx.insert(u)
            vs.viewer = u
            try ctx.save()
            stage = .repo; error = nil
        } catch {
            keychain.delete()
            self.error = "Token rejected. Check the value and try again."
        }
    }

    private func saveRepo() async {
        isValidating = true; defer { isValidating = false }
        let parts = ownerRepo.split(separator: "/")
        guard parts.count == 2 else { error = "Use owner/name format."; return }
        let owner = String(parts[0]); let name = String(parts[1])
        let id = "\(owner)/\(name)"
        let existing = (try? ctx.fetch(FetchDescriptor<Repo>())) ?? []
        for r in existing { r.isActive = false }
        let repo: Repo
        if let already = existing.first(where: { $0.id == id }) {
            already.isActive = true; repo = already
        } else {
            repo = Repo(owner: owner, name: name, isActive: true)
            ctx.insert(repo)
        }
        let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first
        vs?.activeRepoID = repo.id
        try? ctx.save()
        onReady()
    }
}
