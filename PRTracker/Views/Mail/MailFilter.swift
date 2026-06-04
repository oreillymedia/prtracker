import Foundation
import SwiftUI

/// Filter pills shown across the top of the source list.
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

    /// Lane color for the pill dot. `.all`, `.open`, and `.done` have no dot
    /// (they're todo-state filters, not bucket-color filters).
    var dotColor: Color? {
        switch self {
        case .awaitingMe: Lane.attention.color
        case .mine:       Lane.mine.color
        case .recent:     Lane.recent.color
        case .all, .open, .done: nil
        }
    }
}
