import SwiftUI

struct RepoSelectorCard: View {
    let repoSlug: String   // "oreilly/spark-ios"
    let onTap: () -> Void

    private var org: String { repoSlug.split(separator: "/").first.map(String.init) ?? "" }
    private var name: String { repoSlug.split(separator: "/").dropFirst().joined(separator: "/") }
    private var initials: String { name.prefix(2).uppercased() }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.79, green: 0.39, blue: 0.26),
                                     Color(red: 0.48, green: 0.18, blue: 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Text(initials).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(org).font(.system(size: 11)).foregroundStyle(Tokens.textMuted).lineLimit(1)
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
