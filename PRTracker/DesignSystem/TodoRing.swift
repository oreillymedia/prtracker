import SwiftUI

struct TodoRing: View {
    enum RingState { case allResolved, awaitingMe, waiting, empty }

    let done: Int
    let total: Int
    let size: CGFloat
    let state: RingState

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.hairline, lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(arcColor, style: .init(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
            centerLabel
        }
        .frame(width: size, height: size)
    }

    private var progress: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    private var arcColor: Color {
        switch state {
        case .allResolved: return Tokens.approved
        case .awaitingMe:  return Tokens.accent
        case .waiting:     return Tokens.textFaint
        case .empty:       return Tokens.hairline
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if total == 0 {
            Circle().fill(Tokens.textFaint).frame(width: 2, height: 2)
        } else if done == total {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(Tokens.approved)
        } else {
            Text("\(done)/\(total)")
                .font(.system(size: size * 0.42, weight: .bold).monospacedDigit())
                .foregroundStyle(arcColor)
        }
    }
}
