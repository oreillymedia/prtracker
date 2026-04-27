import SwiftUI

struct StatusGauge: View {
    enum Stage { case review, ci, merge }
    enum StageState { case ok, bad, running, inactive }

    let review: StageState
    let ci: StageState
    let merge: StageState

    var body: some View {
        HStack(spacing: 6) {
            bar(.review, review)
            bar(.ci, ci)
            bar(.merge, merge)
        }
    }

    private func bar(_ stage: Stage, _ state: StageState) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(barFill(state)).frame(width: 34, height: 4)
                if state == .running {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)
                        Capsule()
                            .fill(.white.opacity(0.55))
                            .frame(width: 10, height: 4)
                            .offset(x: -10 + phase * 44)
                            .clipShape(Capsule())
                            .mask(Capsule().frame(width: 34, height: 4))
                    }
                }
            }
            Text(label(stage))
                .font(.system(size: 9.5).weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(state == .inactive ? Tokens.textFaint : labelColor(state))
        }
    }

    private func barFill(_ s: StageState) -> Color {
        switch s {
        case .ok: Tokens.approved
        case .bad: Tokens.changes
        case .running: Tokens.pending
        case .inactive: Tokens.hairline
        }
    }
    private func labelColor(_ s: StageState) -> Color {
        switch s {
        case .ok: Tokens.approved
        case .bad: Tokens.changes
        case .running: Tokens.pending
        case .inactive: Tokens.textFaint
        }
    }
    private func label(_ s: Stage) -> String {
        switch s { case .review: "REVIEW"; case .ci: "CI"; case .merge: "MERGE" }
    }
}

#Preview {
    HStack(spacing: 24) {
        StatusGauge(review: .bad, ci: .running, merge: .inactive)
        StatusGauge(review: .ok, ci: .ok, merge: .ok)
        StatusGauge(review: .inactive, ci: .ok, merge: .running)
    }.padding(40).background(Tokens.contentBg)
}
