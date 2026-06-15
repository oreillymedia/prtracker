import Foundation
import SwiftData

@Model
final class Repo {
    @Attribute(.unique) var id: String   // "owner/name"
    var owner: String
    var name: String
    var lastFetchedAt: Date?
    var isEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \PullRequest.repo)
    var pullRequests: [PullRequest] = []

    init(owner: String, name: String, isEnabled: Bool = true) {
        self.id = "\(owner)/\(name)"
        self.owner = owner
        self.name = name
        self.isEnabled = isEnabled
    }
}
