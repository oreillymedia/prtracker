import SwiftUI
import AppKit

enum MenuBarIconRenderer {
    static func image(attentionCount: Int) -> NSImage {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRs")!
        if attentionCount == 0 { return base }
        let composite = NSImage(size: NSSize(width: 18, height: 18))
        composite.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        let badgeRect = NSRect(x: 8, y: 8, width: 10, height: 10)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        let label = "\(min(attentionCount, 9))" + (attentionCount > 9 ? "+" : "")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: NSColor.white]
        (label as NSString).draw(in: badgeRect.insetBy(dx: 1, dy: 0), withAttributes: attrs)
        composite.unlockFocus()
        composite.isTemplate = false
        return composite
    }
}
