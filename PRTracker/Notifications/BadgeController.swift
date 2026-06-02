import AppKit
import Foundation

protocol DockBadgeSetting: AnyObject {
    func setLabel(_ value: String?)
}

final class NSAppDockBadge: DockBadgeSetting {
    func setLabel(_ value: String?) {
        NSApp.dockTile.badgeLabel = value
    }
}

@Observable
final class BadgeController {
    var attentionCount: Int = 0
    var menuBarEnabled: Bool = true
    var dockEnabled: Bool = true

    @ObservationIgnored private let dock: DockBadgeSetting

    init(dock: DockBadgeSetting = NSAppDockBadge()) {
        self.dock = dock
    }

    var menuBarShowsDot: Bool { menuBarEnabled && attentionCount > 0 }
    var dockShowsBadge: Bool { dockEnabled && attentionCount > 0 }

    func apply() {
        dock.setLabel(dockShowsBadge ? "●" : nil)
    }
}
