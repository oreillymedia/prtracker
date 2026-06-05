import SwiftUI
import NukeUI

struct AvatarView: View {
    let user: User
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Tokens.commented)
            if let url = user.avatarURL {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .clipShape(Circle())
            } else {
                Text(String(user.login.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5).weight(.semibold))
                    .foregroundStyle(.white)
            }
        }.frame(width: size, height: size)
    }
}
