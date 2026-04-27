import SwiftUI

struct QuickReply: View {
    let viewer: User?
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let v = viewer { AvatarView(user: v, size: 22); Text("Reply as \(v.name ?? v.login)").metaText() }
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
            HStack {
                Spacer()
                Button("Approve") {}.buttonStyle(.bordered).disabled(true).help("Coming soon")
                Button("Request changes") {}.buttonStyle(.bordered).disabled(true).help("Coming soon")
                Button("Comment") {}.buttonStyle(.borderedProminent).disabled(true).help("Coming soon")
            }
        }
        .padding(12)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
    }
}
