import SwiftUI

/// 8pt unread indicator. When `on`, shows a solid `unreadDot` fill plus a soft 2pt ring.
/// When `off`, occupies the same space transparently so layout doesn't shift.
struct UnreadDot: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? Tokens.unreadDot : .clear)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(on ? Tokens.unreadDot.opacity(0.22) : .clear, lineWidth: 2)
                    .padding(-1)
            )
    }
}
