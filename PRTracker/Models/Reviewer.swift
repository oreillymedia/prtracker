import Foundation
import SwiftData

@Model
final class Reviewer {
    var user: User
    var stateRaw: String
    var pr: PullRequest

    var state: ReviewState {
        get { ReviewState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(user: User, state: ReviewState, pr: PullRequest) {
        self.user = user
        self.stateRaw = state.rawValue
        self.pr = pr
    }
}
