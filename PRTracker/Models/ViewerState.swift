import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool
    var themePreferenceRaw: String = "system"
    var menuBarBadgeEnabled: Bool = true
    var dockBadgeEnabled: Bool = true

    enum ThemePreference: String { case system, light, dark }
    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    init(viewer: User? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system", menuBarBadgeEnabled: Bool = true, dockBadgeEnabled: Bool = true) {
        self.viewer = viewer
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
        self.menuBarBadgeEnabled = menuBarBadgeEnabled
        self.dockBadgeEnabled = dockBadgeEnabled
    }
}
