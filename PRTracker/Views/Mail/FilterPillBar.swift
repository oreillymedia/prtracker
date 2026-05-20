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
        Button {
            active = filter
        } label: {
            HStack(spacing: 5) {
                if let dot = filter.dotColor {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(filter.label).font(.system(size: 11.5, weight: .semibold))
                if let count = counts[filter], count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(isActive ? Tokens.contentBg.opacity(0.7) : Tokens.textMuted)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .foregroundStyle(isActive ? Tokens.contentBg : Tokens.text)
            .background(
                Capsule().fill(isActive ? Tokens.text : Tokens.cardBg)
            )
            .overlay(
                Capsule().stroke(isActive ? .clear : Tokens.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
