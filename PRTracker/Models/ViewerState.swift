import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var tokenTypeRaw: String?
    var tokenScopesRaw: String = ""
    var tokenExpirationDate: Date?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool
    var themePreferenceRaw: String = "system"
    var menuBarBadgeEnabled: Bool = true
    var dockBadgeEnabled: Bool = true

    enum ThemePreference: String { case system, light, dark }
    var tokenType: GitHubTokenType? {
        get { tokenTypeRaw.flatMap(GitHubTokenType.init(rawValue:)) }
        set { tokenTypeRaw = newValue?.rawValue }
    }

    var tokenScopes: [String] {
        get { tokenScopesRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        set { tokenScopesRaw = newValue.joined(separator: ",") }
    }

    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    init(viewer: User? = nil, tokenTypeRaw: String? = nil, tokenScopesRaw: String = "", tokenExpirationDate: Date? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system", menuBarBadgeEnabled: Bool = true, dockBadgeEnabled: Bool = true) {
        self.viewer = viewer
        self.tokenTypeRaw = tokenTypeRaw
        self.tokenScopesRaw = tokenScopesRaw
        self.tokenExpirationDate = tokenExpirationDate
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
        self.menuBarBadgeEnabled = menuBarBadgeEnabled
        self.dockBadgeEnabled = dockBadgeEnabled
    }
}
