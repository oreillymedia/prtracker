import SwiftUI

struct FilterPillBar: View {
    @Binding var active: MailFilter
    let counts: [MailFilter: Int]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(MailFilter.allCases) { filter in
                    pill(filter)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder
    private func pill(_ filter: MailFilter) -> some View {
        let isActive = (filter == active)
        let count = counts[filter] ?? 0
        let isAwaitingMe = (filter == .awaitingMe && count > 0)

        let bg: Color = {
            if isActive {
                return isAwaitingMe ? Tokens.accent : Tokens.text
            }
            if isAwaitingMe { return Tokens.accentBg }
            return Tokens.cardBg
        }()

        let fg: Color = {
            if isActive { return .white }
            if isAwaitingMe { return Tokens.accent }
            return Tokens.text
        }()

        let weight: Font.Weight = isAwaitingMe ? .bold : .semibold

        Button { active = filter } label: {
            HStack(spacing: 5) {
                if let dot = filter.dotColor {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(filter.label).font(.system(size: 11.5, weight: weight))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(isActive ? .white.opacity(0.85) : (isAwaitingMe ? Tokens.accent : Tokens.textMuted))
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(isActive ? .clear : Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
