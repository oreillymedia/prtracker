import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var activeRepoID: String?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool
    var themePreferenceRaw: String = "system"
    var notificationLevelRaw: String = NotificationLevel.personal.rawValue
    var menuBarBadgeEnabled: Bool = true
    var dockBadgeEnabled: Bool = true

    enum ThemePreference: String { case system, light, dark }
    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    var notificationLevel: NotificationLevel {
        get { NotificationLevel(rawValue: notificationLevelRaw) ?? .personal }
        set { notificationLevelRaw = newValue.rawValue }
    }

    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system", notificationLevelRaw: String = NotificationLevel.personal.rawValue, menuBarBadgeEnabled: Bool = true, dockBadgeEnabled: Bool = true) {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
        self.notificationLevelRaw = notificationLevelRaw
        self.menuBarBadgeEnabled = menuBarBadgeEnabled
        self.dockBadgeEnabled = dockBadgeEnabled
    }
}
