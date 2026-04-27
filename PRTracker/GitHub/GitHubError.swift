import Foundation

enum GitHubError: Error, Equatable {
    case unauthorized
    case repoNotFound
    case rateLimited(resetAt: Date)
    case network(message: String)
    case decoding(message: String)
    case notModified
}
