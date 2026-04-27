import SwiftUI

@Observable
final class MenuBarBadge {
    var count: Int = 0
}

struct MenuBarLabel: View {
    let badge: MenuBarBadge
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(attentionCount: badge.count))
    }
}
