import SwiftUI

struct FeedSection<Content: View>: View {
    let lane: Lane
    let title: String
    let count: Int
    @Binding var collapsed: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10).weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(Tokens.textMuted)
                    RoundedRectangle(cornerRadius: 2).fill(lane.color).frame(width: 8, height: 8)
                    Text(title).sectionHeader().foregroundStyle(Tokens.text)
                    if count > 0 { CountPill(count: count, tint: lane.color) }
                    Spacer()
                }
            }.buttonStyle(.plain)
            if !collapsed { content() }
        }
    }
}

struct CountPill: View {
    let count: Int
    let tint: Color
    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5).weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
