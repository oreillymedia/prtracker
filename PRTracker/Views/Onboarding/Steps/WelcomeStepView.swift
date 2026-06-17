import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Tokens.accent, Tokens.accent.opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "arrow.triangle.pull").font(.system(size: 24, weight: .medium)).foregroundStyle(.white))
            Text("Welcome to PR Tracker").font(.system(size: 20, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Keep an eye on your GitHub pull requests across every repository you care about — reviews, comments, CI, and merges, all in one place.")
                .font(.system(size: 13)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                bullet("key.horizontal", "Connect with a GitHub token")
                bullet("folder", "Add the repositories you want to follow")
                bullet("bell", "Choose how each one notifies you")
            }.padding(.top, 4)
            Spacer()
        }
    }
    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Tokens.accent).frame(width: 18)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
        }
    }
}
