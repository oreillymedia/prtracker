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

    /// True from the moment a sync finds policy-passing activity until the user
    /// looks: the popover opens or the app becomes active. Drives the menu-bar icon.
    var hasNewActivity: Bool = false

    @ObservationIgnored private let dock: DockBadgeSetting

    init(dock: DockBadgeSetting = NSAppDockBadge()) {
        self.dock = dock
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dock.setLabel(nil)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.clearNewActivity()
        }
    }

    var menuBarShowsDot: Bool { menuBarEnabled && hasNewActivity }

    func noteNewActivity() { hasNewActivity = true }
    func clearNewActivity() { hasNewActivity = false }

    var dockShowsBadge: Bool { dockEnabled && attentionCount > 0 }

    func apply() {
        dock.setLabel(dockShowsBadge ? "●" : nil)
    }
}
