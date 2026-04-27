import SwiftUI

extension View {
    func cardTitle(unread: Bool) -> some View {
        font(.system(size: 13.5, weight: unread ? .semibold : .medium))
    }
    func sectionHeader() -> some View {
        font(.system(size: 12.5, weight: .bold))
    }
    func metaText() -> some View {
        font(.system(size: 11.5, weight: .medium))
    }
    func microText() -> some View {
        font(.system(size: 10.5))
    }
    func monoText() -> some View {
        font(.system(size: 10.5, design: .monospaced))
    }
}
