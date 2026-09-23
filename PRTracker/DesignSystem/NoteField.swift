import SwiftUI

/// Private, local-only free text. Same look everywhere a note appears.
struct NoteField: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(Tokens.textFaint).padding(.top, 3)
            TextField("Private note — never sent to GitHub", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...8)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Tokens.contentBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
    }
}
