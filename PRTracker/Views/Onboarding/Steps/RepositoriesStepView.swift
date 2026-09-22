import SwiftUI

struct RepositoriesStepView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var model: OnboardingModel
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add repositories").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Enter repositories as **owner/name**. We'll verify each one before adding it. You can track as many as you like.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("owner/name", text: $model.newRepo).textFieldStyle(.roundedBorder)
                    .onSubmit { onAdd() }
                Button { onAdd() } label: {
                    if model.isCheckingRepo { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .disabled(RepoRef.parse(model.newRepo) == nil || model.isCheckingRepo)
            }
            if let problem = model.addProblem {
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

            if model.pending.isEmpty {
                Text("No repositories yet.").font(.system(size: 12)).foregroundStyle(Tokens.textFaint).padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.pending) { repo in
                            HStack(spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
                                Text(repo.id).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
                                Spacer()
                                Button { model.removeRepo(id: repo.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Tokens.textFaint)
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
            }
            Spacer()
        }
    }
}
