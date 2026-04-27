import Foundation
import SwiftData

@Model
final class Repo {
    @Attribute(.unique) var id: String   // "owner/name"
    var owner: String
    var name: String
    var lastFetchedAt: Date?
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \PullRequest.repo)
    var pullRequests: [PullRequest] = []

    init(owner: String, name: String, isActive: Bool = false) {
        self.id = "\(owner)/\(name)"
        self.owner = owner
        self.name = name
        self.isActive = isActive
    }
}
