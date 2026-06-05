import SwiftUI

struct TodoRing: View {
    enum RingState { case allResolved, awaitingMe, waiting, empty, ciFailed }

    let done: Int
    let total: Int
    let size: CGFloat
    let state: RingState
    var inProgressIcon: String? = nil
    /// When true (selected row of a focused list), render in white so the ring
    /// reads on the accent selection capsule.
    var highlighted: Bool = false
    /// Animate the progress arc when `progress` changes. Disable where the ring
    /// is rebuilt frequently and the sweep is distracting (e.g. the detail header).
    var animated: Bool = true

    var body: some View {
        ZStack {
            Circle().stroke(highlighted ? Color.white.opacity(0.3) : Tokens.hairline, lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: state == .ciFailed ? 1 : progress)
                .stroke(arcColor, style: .init(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animated ? .easeOut(duration: 0.35) : nil, value: progress)
            centerLabel
        }
        .frame(width: size, height: size)
    }

    private var progress: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    private var arcColor: Color {
        if highlighted { return .white }
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
                .foregroundStyle(highlighted ? .white : Tokens.changes)
        } else if total == 0 {
            Circle().fill(highlighted ? Color.white.opacity(0.7) : Tokens.textFaint).frame(width: 2, height: 2)
        } else if done == total {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(highlighted ? .white : Tokens.approved)
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
