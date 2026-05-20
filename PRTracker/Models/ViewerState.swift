import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var activeRepoID: String?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool
    var themePreferenceRaw: String = "system"

    enum ThemePreference: String { case system, light, dark }
    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system") {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
    }
}
