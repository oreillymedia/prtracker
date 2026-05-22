import SwiftUI

struct TodoCheckbox: View {
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.04)
                    .fill(isOn ? Tokens.approved : Color.clear)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5.04)
                            .stroke(isOn ? .clear : Tokens.borderStrong, lineWidth: 1.5)
                    )
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}
