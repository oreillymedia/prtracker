import Foundation

/// Filter options for the PR list, shown in the sidebar toolbar picker.
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case awaitingMe, mine, open, all, done, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        "All"
        case .awaitingMe: "Awaiting me"
        case .open:       "Open"
        case .mine:       "Mine"
        case .done:       "Done"
        case .recent:     "Merged"
        }
    }
}
