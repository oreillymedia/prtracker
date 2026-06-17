import SwiftUI

struct ConnectStepView: View {
    @Bindable var model: OnboardingModel
    var onValidate: () -> Void

    private let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=PRTracker")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your GitHub account").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("PR Tracker needs a personal access token with the **repo** scope to read your pull requests. Fine-grained tokens with read access to pull requests also work.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
            Link(destination: tokenURL) {
                HStack(spacing: 5) { Image(systemName: "arrow.up.forward.square"); Text("Create a token on GitHub") }
                    .font(.system(size: 12.5, weight: .medium))
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
                Button("Validate") { onValidate() }
                    .disabled(model.token.isEmpty || model.isValidating)
            }
            if let err = model.connectError {
                Text(err).font(.system(size: 11, weight: .medium)).foregroundStyle(Tokens.changes)
            }
            Spacer()
        }
    }
}
