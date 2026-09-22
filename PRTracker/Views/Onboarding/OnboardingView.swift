import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let mode: OnboardingModel.Mode
    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    @State private var model: OnboardingModel
    @State private var didSeed = false

    init(mode: OnboardingModel.Mode, keychain: Keychain, client: GitHubClient, coordinator: SyncCoordinator) {
        self.mode = mode
        self.keychain = keychain
        self.client = client
        self.coordinator = coordinator
        _model = State(initialValue: OnboardingModel(mode: mode))
    }

    private let steps = OnboardingModel.Step.allCases

    var body: some View {
        HStack(spacing: 0) {
            OnboardingStepRail(steps: steps, current: model.step) { step in
                if step.rawValue <= model.step.rawValue { model.step = step }
            }
            .background(Tokens.cardBg)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                content.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                navBar.padding(.horizontal, 24).padding(.vertical, 14)
            }
        }
        .frame(width: 660, height: 480)
        .task {
            if !didSeed {
                didSeed = true
                if mode == .reconfigure { model.seed(from: ctx) }
                model.notifStatus = await NotificationAuthorization().currentStatus()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStepView()
        case .connect: ConnectStepView(model: model, onValidate: { Task { await validateToken() } })
        case .repositories: RepositoriesStepView(model: model, onAdd: { Task { await addRepo() } })
        case .notifications: NotificationsStepView(model: model, onRequestPermission: { Task { await requestPermission() } })
        }
    }

    private var navBar: some View {
        HStack {
            // Cancel is available in both modes so the user is never trapped —
            // e.g. stuck at the repositories step when their token can't reach a
            // repo. First-run's interactive dismissal stays disabled, so this
            // button is the deliberate exit.
            Button("Cancel") { dismiss() }
            if model.step != .welcome {
                Button("Back") { if let prev = OnboardingModel.Step(rawValue: model.step.rawValue - 1) { model.step = prev } }
            }
            Spacer()
            if model.step == .notifications {
                Button(mode == .reconfigure ? "Save" : "Finish") { finish() }
                    .buttonStyle(.glassProminent).controlSize(.large)
            } else {
                Button("Continue") { advance() }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(!model.canContinue(from: model.step))
            }
        }
    }

    private func advance() {
        guard model.canContinue(from: model.step),
              let next = OnboardingModel.Step(rawValue: model.step.rawValue + 1) else { return }
        model.step = next
    }

    private func finish() {
        model.commit(into: ctx)
        if mode == .firstRun {
            coordinator.start()
        } else {
            coordinator.reconnected()
        }
        // Onboarding is always presented as a sheet now (first-run included),
        // so both modes dismiss; MainView shows the configured app behind it.
        dismiss()
    }

    private func validateToken() async {
        let token = GitHubTokenMetadata.normalizedToken(model.token)
        guard !token.isEmpty else { return }
        model.isValidating = true; defer { model.isValidating = false }
        model.connectProblem = nil
        keychain.save(token)

        let result = await ConnectionCheck(client: client, token: token).run(repos: [])
        model.connectionResult = result
        if let failure = result.items.first(where: { $0.status == .failure }) {
            model.connectProblem = GitHubErrorPresentation(title: failure.title, detail: failure.message, action: failure.action)
            model.connectError = failure.message
            if case .network = result.identityError { return }
            if case .decoding = result.identityError { return }
            keychain.delete()
            return
        }

        guard let viewer = result.viewer else { return }
        model.applyValidatedViewer(viewer, tokenMetadata: result.metadata)
        model.token = ""
    }

    private func addRepo() async {
        guard let ref = RepoRef.parse(model.newRepo) else { return }
        if model.pending.contains(where: { $0.id == ref.slug }) {
            model.addError = "That repository is already in your list."; return
        }
        model.isCheckingRepo = true; defer { model.isCheckingRepo = false }
        model.addError = nil
        model.addProblem = nil
        do {
            guard let token = keychain.load() else {
                throw GitHubError.unauthorized
            }
            let result = await ConnectionCheck(client: client, token: token).run(repos: [ref])
            if let failure = result.items.first(where: { $0.status == .failure }) {
                model.addProblem = GitHubErrorPresentation(title: failure.title, detail: failure.message, action: failure.action)
                model.addError = failure.message
                return
            }
            _ = model.addRepo(model.newRepo)
            model.newRepo = ""
        } catch let error as GitHubError {
            model.addProblem = error.userFacing
            model.addError = error.userFacing.detail
        } catch {
            model.addProblem = GitHubError.network(message: error.localizedDescription).userFacing
            model.addError = "Couldn't verify \(ref.slug). Check your connection and try again."
        }
    }

    private func requestPermission() async {
        model.notifStatus = await NotificationAuthorization().requestAuthorization()
    }
}
