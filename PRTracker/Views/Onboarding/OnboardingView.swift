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
            if mode == .reconfigure { Button("Cancel") { dismiss() } }
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
            Task { await coordinator.refresh() }
            dismiss()
        }
    }

    private func validateToken() async {
        model.isValidating = true; defer { model.isValidating = false }
        keychain.save(model.token)
        do {
            let dto = try await client.validate()
            model.applyValidatedViewer(dto)
            model.token = ""
        } catch {
            keychain.delete()
            model.connectError = "That token was rejected. Check it has repo access and try again."
        }
    }

    private func addRepo() async {
        guard let ref = RepoRef.parse(model.newRepo) else { return }
        if model.pending.contains(where: { $0.id == ref.slug }) {
            model.addError = "That repository is already in your list."; return
        }
        model.isCheckingRepo = true; defer { model.isCheckingRepo = false }
        model.addError = nil
        do {
            _ = try await client.repository(ref)
            _ = model.addRepo(model.newRepo)
            model.newRepo = ""
        } catch GitHubError.repoNotFound {
            model.addError = "Couldn't find \(ref.slug), or your token can't access it."
        } catch GitHubError.unauthorized {
            model.addError = "Your token can't access \(ref.slug)."
        } catch {
            model.addError = "Couldn't reach GitHub. Check your connection and try again."
        }
    }

    private func requestPermission() async {
        model.notifStatus = await NotificationAuthorization().requestAuthorization()
    }
}
