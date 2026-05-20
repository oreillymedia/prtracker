import SwiftUI

struct MailEmptyDetailView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 28))
                .foregroundStyle(Tokens.textFaint.opacity(0.5))
            Text("No pull request selected.")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.contentBg)
    }
}
