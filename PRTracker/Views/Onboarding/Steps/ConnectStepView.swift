import SwiftUI

struct ConnectStepView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var model: OnboardingModel
    var onValidate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your GitHub account").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Create a classic personal access token with the **repo** scope, then authorize it for the oreillymedia organization.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
            Link(destination: GitHubTokenGuide.tokenURL) {
                HStack(spacing: 5) { Image(systemName: "arrow.up.forward.square"); Text("Create token") }
                    .font(.system(size: 12.5, weight: .medium))
            }
            Text("Or, follow these steps:")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(GitHubTokenGuide.checklist.enumerated()), id: \.offset) { index, item in
                    SwiftUI.Label(item, systemImage: "\(index + 1).circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(GitHubTokenGuide.fineGrainedNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Tokens.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let v = model.viewer, let user = model.displayUser {
                HStack(spacing: 9) {
                    AvatarView(user: user, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(v.name ?? v.login).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.text)
                        Text("@\(v.login)").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.approved)
                }
                .padding(10).background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                if model.mode == .reconfigure {
                    Text("Paste a new token below to switch accounts.")
                        .font(.system(size: 11)).foregroundStyle(Tokens.textFaint)
                }
            }

            HStack {
                SecureField("ghp_…", text: $model.token).textFieldStyle(.roundedBorder)
                    .onSubmit { if !model.token.isEmpty && !model.isValidating { onValidate() } }
                Button("Validate") { onValidate() }
                    .disabled(model.token.isEmpty || model.isValidating)
            }
            if let problem = model.connectProblem {
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
            if let warning = model.connectionResult?.items.first(where: { $0.status == .warning }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.title).font(.system(size: 11, weight: .semibold))
                    Text(warning.message).font(.system(size: 11))
                    if let action = warning.action {
                        Button(action.label) { openURL(action.url) }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.link)
                    }
                }
                .foregroundStyle(Tokens.pending)
            }
            Spacer()
        }
    }
}
