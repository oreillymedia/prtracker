import Foundation
import SwiftData

@Observable
final class AppState {
    @ObservationIgnored
    private let defaults: UserDefaults

    var activeFilter: MailFilter {
        didSet { defaults.set(activeFilter.rawValue, forKey: Keys.activeFilter) }
    }
    var selectedPRID: String? {
        didSet { defaults.set(selectedPRID, forKey: Keys.selectedPRID) }
    }
    var rateLimitRemaining: Int? = nil
    var rateLimitResetAt: Date? = nil

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.activeFilter) ?? ""
        self.activeFilter = MailFilter(rawValue: raw) ?? .awaitingMe
        self.selectedPRID = defaults.string(forKey: Keys.selectedPRID)
    }

    private enum Keys {
        static let activeFilter = "AppState.activeFilter"
        static let selectedPRID = "AppState.selectedPRID"
    }
}
