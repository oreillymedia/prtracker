import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var activeRepoID: String?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool

    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false) {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
