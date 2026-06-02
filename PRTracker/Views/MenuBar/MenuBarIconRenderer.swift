import SwiftUI
import AppKit

enum MenuBarIconRenderer {
    static func image(showDot: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRs")!
        if !showDot { return base }
        let composite = NSImage(size: NSSize(width: 18, height: 18))
        composite.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        let dot = NSRect(x: 11, y: 11, width: 7, height: 7)
        NSColor(Tokens.accent).setFill()
        NSBezierPath(ovalIn: dot).fill()
        composite.unlockFocus()
        composite.isTemplate = false
        return composite
    }
}
