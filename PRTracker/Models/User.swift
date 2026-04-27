import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var login: String
    var name: String?
    var avatarURL: URL?

    init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}
