import SwiftUI

struct AccountFooter: View {
    let viewer: User?
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let viewer {
                AvatarView(user: viewer, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewer.name ?? viewer.login).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                    Text("@\(viewer.login)").font(.system(size: 10.5)).foregroundStyle(Tokens.textMuted).lineLimit(1)
                }
            } else {
                Text("Not signed in").font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 0)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tokens.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
