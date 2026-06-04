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
    // MARK: - System-backed surfaces & separators
    // Formerly hand-tuned translucency that simulated depth. Now mapped onto
    // AppKit semantic colors so they adapt to Increase Contrast / Reduce
    // Transparency automatically. Glass for the navigation layer is provided by
    // NavigationSplitView / .inspector / .toolbar — not by these tokens.
    static let windowBg     = Color(nsColor: .windowBackgroundColor)
    static let panelBg      = Color(nsColor: .windowBackgroundColor)   // transitional; uses removed in Tasks 3–4
    static let sidebarBg    = Color(nsColor: .windowBackgroundColor)   // transitional; use removed in Task 2
    static let contentBg    = Color(nsColor: .textBackgroundColor)     // inset field / nested block surface
    static let border       = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .separatorColor)
    static let hairline     = Color(nsColor: .separatorColor).opacity(0.6)
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
    static let cardBg       = Color(nsColor: .controlBackgroundColor)
    static let unreadDot    = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),
                                                       dark:  NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)))
    static let newHighlight = Color(red: 0, green: 0.48, blue: 1, opacity: 0.06)   // same in both modes

    // MARK: - Mail-redesign additions

    static let approvedBg   = Color(nsColor: .dynamic(light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 0.10),
                                                       dark:  NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 0.15)))
    static let changesBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 0.10),
                                                       dark:  NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 0.15)))
    static let pendingBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.60, green: 0.40, blue: 0.00, alpha: 0.10),
                                                       dark:  NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 0.15)))
    static let commentedBg  = Color(nsColor: .dynamic(light: NSColor(red: 0.43, green: 0.47, blue: 0.51, alpha: 0.10),
                                                       dark:  NSColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.15)))
    static let accentText   = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.38, blue: 0.80, alpha: 1),
                                                       dark:  NSColor(red: 0.39, green: 0.66, blue: 1.00, alpha: 1)))
    static let rowHover     = Color(nsColor: .dynamic(light: NSColor(white: 0, alpha: 0.03),
                                                       dark:  NSColor(white: 1, alpha: 0.04)))
    static let rowSelect    = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 0.10),
                                                       dark:  NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 0.20)))
}
