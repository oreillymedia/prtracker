import SwiftUI

struct MenuBarLabel: View {
    let controller: BadgeController
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(showDot: controller.menuBarShowsDot))
    }
}
