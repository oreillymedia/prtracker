import SwiftUI

/// Renders a comment body using SwiftUI's built-in markdown parsing.
/// Inline elements (bold, italic, links, inline code, strikethrough) parse.
/// Block elements (headings, lists, fenced code blocks) render as literal
/// markdown text — accepted per the design directive.
struct MarkdownText: View {
    let raw: String

    var body: some View {
        Text(attributed)
            .font(.system(size: 13))
            .foregroundStyle(Tokens.text)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts))
            ?? AttributedString(raw)
    }
}
