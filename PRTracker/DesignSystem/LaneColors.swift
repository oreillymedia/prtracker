import SwiftUI

enum Lane: String, CaseIterable {
    case attention, review, mine, involved, mentions, recent

    var color: Color {
        switch self {
        case .attention: Color(red: 1.00, green: 0.58, blue: 0.00)
        case .review:    Color(red: 0.04, green: 0.52, blue: 1.00)
        case .mine:      Color(red: 0.19, green: 0.72, blue: 0.30)
        case .involved:  Color(red: 0.56, green: 0.56, blue: 0.58)
        case .mentions:  Color(red: 0.75, green: 0.35, blue: 0.95)
        case .recent:    Color(red: 0.51, green: 0.31, blue: 0.87)
        }
    }

    var label: String {
        switch self {
        case .attention: "Needs my attention"
        case .review:    "Needs my review"
        case .mine:      "My open PRs"
        case .involved:  "Others' PRs"
        case .mentions:  "Mentions"
        case .recent:    "Recently merged"
        }
    }
}
