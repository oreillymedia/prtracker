import Foundation
import SwiftData

@Model
final class CIRun {
    var name: String
    var stateRaw: String
    var durationSeconds: Int?
    var pr: PullRequest

    var state: CIState {
        get { CIState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(name: String, state: CIState, pr: PullRequest, durationSeconds: Int? = nil) {
        self.name = name
        self.stateRaw = state.rawValue
        self.pr = pr
        self.durationSeconds = durationSeconds
    }
}
