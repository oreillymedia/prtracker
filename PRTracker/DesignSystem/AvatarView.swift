import SwiftUI

struct AvatarView: View {
    let user: User
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Tokens.commented)
            if let url = user.avatarURL {
                AsyncImage(url: url) { img in img.resizable() } placeholder: { Color.clear }
                    .clipShape(Circle())
            } else {
                Text(String(user.login.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5).weight(.semibold))
                    .foregroundStyle(.white)
            }
        }.frame(width: size, height: size)
    }
}
