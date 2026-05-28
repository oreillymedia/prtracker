import SwiftUI

struct TodoRing: View {
    enum RingState { case allResolved, awaitingMe, waiting, empty, ciFailed }

    let done: Int
    let total: Int
    let size: CGFloat
    let state: RingState
    var inProgressIcon: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.hairline, lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: state == .ciFailed ? 1 : progress)
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
        case .ciFailed:    return Tokens.changes
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if state == .ciFailed {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(Tokens.changes)
        } else if total == 0 {
            Circle().fill(Tokens.textFaint).frame(width: 2, height: 2)
        } else if done == total {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(Tokens.approved)
        } else if let inProgressIcon {
            Image(systemName: inProgressIcon)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(arcColor)
        } else {
            Text("\(done)/\(total)")
                .font(.system(size: size * 0.42, weight: .bold).monospacedDigit())
                .foregroundStyle(arcColor)
        }
    }
}
