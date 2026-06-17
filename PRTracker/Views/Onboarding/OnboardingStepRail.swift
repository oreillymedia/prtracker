import SwiftUI

/// Left rail listing the onboarding steps with progress state. Visited/active
/// steps are tappable to go back; upcoming steps are disabled.
struct OnboardingStepRail: View {
    let steps: [OnboardingModel.Step]
    let current: OnboardingModel.Step
    let onSelect: (OnboardingModel.Step) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps) { step in
                let state = state(for: step)
                Button { if state != .upcoming { onSelect(step) } } label: {
                    HStack(spacing: 9) {
                        badge(step: step, state: state)
                        Text(step.title)
                            .font(.system(size: 12.5, weight: state == .active ? .semibold : .regular))
                            .foregroundStyle(state == .upcoming ? Tokens.textFaint : Tokens.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(state == .active ? Tokens.accentBg : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state == .upcoming)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 168)
    }

    private enum StepState { case done, active, upcoming }
    private func state(for step: OnboardingModel.Step) -> StepState {
        if step.rawValue < current.rawValue { return .done }
        if step == current { return .active }
        return .upcoming
    }

    @ViewBuilder private func badge(step: OnboardingModel.Step, state: StepState) -> some View {
        ZStack {
            Circle().fill(fill(state)).frame(width: 20, height: 20)
            if state == .done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(step.rawValue + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(state == .active ? .white : Tokens.textMuted)
            }
        }
    }
    private func fill(_ s: StepState) -> Color {
        switch s {
        case .done: Tokens.approved
        case .active: Tokens.accent
        case .upcoming: Tokens.hairline
        }
    }
}
