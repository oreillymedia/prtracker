import Foundation
import SwiftData

@Model
final class Label {
    var name: String
    var pr: PullRequest

    init(name: String, pr: PullRequest) {
        self.name = name
        self.pr = pr
    }
}
