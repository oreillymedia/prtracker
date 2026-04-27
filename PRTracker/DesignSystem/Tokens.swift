import SwiftUI
import AppKit

private extension NSColor {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }
}

enum Tokens {
    static let windowBg     = Color(nsColor: .dynamic(light: .white,
                                                       dark:  NSColor(white: 0.11, alpha: 1)))
    static let panelBg      = Color(nsColor: .dynamic(light: NSColor(white: 0.96, alpha: 0.85),
                                                       dark:  NSColor(white: 0.11, alpha: 0.85)))
    static let contentBg    = Color(nsColor: .dynamic(light: .white,
                                                       dark:  NSColor(white: 0.11, alpha: 1)))
    static let sidebarBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.82, green: 0.88, blue: 0.96, alpha: 0.45),
                                                       dark:  NSColor(white: 0.17, alpha: 0.55)))
    static let border       = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.08),
                                                       dark:  NSColor(white: 1,   alpha: 0.10)))
    static let borderStrong = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.14),
                                                       dark:  NSColor(white: 1,   alpha: 0.16)))
    static let hairline     = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.06),
                                                       dark:  NSColor(white: 1,   alpha: 0.06)))
    static let text         = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.88),
                                                       dark:  NSColor(white: 1,   alpha: 0.92)))
    static let textMuted    = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.56),
                                                       dark:  NSColor(white: 1,   alpha: 0.60)))
    static let textFaint    = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.38),
                                                       dark:  NSColor(white: 1,   alpha: 0.40)))
    static let accent       = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),
                                                       dark:  NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)))
    static let accentBg     = Color(red: 0, green: 0.48, blue: 1, opacity: 0.10)   // same in both modes
    static let approved     = Color(nsColor: .dynamic(light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 1),
                                                       dark:  NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1)))
    static let changes      = Color(nsColor: .dynamic(light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 1),
                                                       dark:  NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1)))
    static let pending      = Color(nsColor: .dynamic(light: NSColor(red: 0.60, green: 0.40, blue: 0.00, alpha: 1),
                                                       dark:  NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 1)))
    static let commented    = Color(nsColor: .dynamic(light: NSColor(red: 0.43, green: 0.47, blue: 0.51, alpha: 1),
                                                       dark:  NSColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)))
    static let cardBg       = Color(nsColor: .dynamic(light: .white,
                                                       dark:  NSColor(white: 0.17, alpha: 1)))
    static let unreadDot    = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),
                                                       dark:  NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)))
    static let newHighlight = Color(red: 0, green: 0.48, blue: 1, opacity: 0.06)   // same in both modes
}
