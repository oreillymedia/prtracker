import Foundation
import SwiftData

@Model
final class CIRun {
    var checkRunID: Int?
    var name: String
    var stateRaw: String
    var durationSeconds: Int?
    var pr: PullRequest

    var state: CIState {
        get { CIState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(checkRunID: Int? = nil, name: String, state: CIState, pr: PullRequest, durationSeconds: Int? = nil) {
        self.checkRunID = checkRunID
        self.name = name
        self.stateRaw = state.rawValue
        self.pr = pr
        self.durationSeconds = durationSeconds
    }
}
