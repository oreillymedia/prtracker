import Foundation
import SwiftUI

/// Filter pills shown across the top of the source list. `all` aggregates everything;
/// every other case corresponds 1:1 to a `Section` produced by `Classifier`.
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case all, attention, review, mentions, mine, involved, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       "All"
        case .attention: "Attention"
        case .review:    "Review"
        case .mentions:  "Mentions"
        case .mine:      "Mine"
        case .involved:  "Involved"
        case .recent:    "Merged"
        }
    }

    /// The `Section` this filter selects, or `nil` for `.all`.
    var section: Section? {
        switch self {
        case .all:       nil
        case .attention: .attention
        case .review:    .review
        case .mentions:  .mentions
        case .mine:      .mine
        case .involved:  .involved
        case .recent:    .recent
        }
    }

    /// Dot color rendered on the pill (and on the row's priority rail).
    /// Hidden on `.all`.
    var dotColor: Color? {
        section?.lane.color
    }
}
