import SwiftUI

/// Three 7pt circles: Review → CI → Merge. Each dot is filled when its stage has a state,
/// outlined when empty. A pulsing animation plays on running dots.
struct MiniGaugeDots: View {
    let pr: PullRequest

    private enum DotState { case empty, passed, failed, running, neutral }

    var body: some View {
        HStack(spacing: 3) {
            dot(for: reviewState)
            dot(for: ciState)
            dot(for: mergeState)
        }
        .help(tooltip)
    }

    @ViewBuilder
    private func dot(for state: DotState) -> some View {
        switch state {
        case .empty:
            Circle().stroke(Tokens.borderStrong, lineWidth: 1).frame(width: 7, height: 7)
        case .passed:
            Circle().fill(Tokens.approved).frame(width: 7, height: 7)
        case .failed:
            Circle().fill(Tokens.changes).frame(width: 7, height: 7)
        case .running:
            Circle().fill(Tokens.pending).frame(width: 7, height: 7)
                .modifier(PulseModifier())
        case .neutral:
            Circle().fill(Tokens.commented).frame(width: 7, height: 7)
        }
    }

    private var reviewState: DotState {
        switch pr.reviewState {
        case .approved:          .passed
        case .changesRequested:  .failed
        case .commented:         .neutral
        case .pending, .none:    .empty
        }
    }

    private var ciState: DotState {
        if pr.ciFail > 0 { return .failed }
        if pr.ciRunning > 0 { return .running }
        if pr.ciPass > 0 { return .passed }
        return .empty
    }

    private var mergeState: DotState {
        switch pr.mergeable {
        case .clean:              .passed
        case .conflicts, .blocked: .failed
        case .unknown:            .empty
        }
    }

    private var tooltip: String {
        "Review \(label(reviewState)) · CI \(label(ciState)) · Merge \(label(mergeState))"
    }

    private func label(_ s: DotState) -> String {
        switch s {
        case .empty:   "—"
        case .passed:  "passed"
        case .failed:  "failed"
        case .running: "running"
        case .neutral: "commented"
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
