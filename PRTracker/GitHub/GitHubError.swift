import Foundation

enum GitHubError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case ssoRequired(authorizeURL: URL)
    case repoNotFound
    case rateLimited(resetAt: Date)
    case network(message: String)
    case decoding(message: String)
    case notModified
}

struct GitHubErrorAction: Equatable, Sendable {
    let label: String
    let url: URL
}

struct GitHubErrorPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let action: GitHubErrorAction?
}

extension GitHubError {
    var isPermissionGap: Bool {
        switch self {
        case .forbidden, .ssoRequired, .repoNotFound: return true
        default: return false
        }
    }

    var userFacing: GitHubErrorPresentation {
        switch self {
        case .unauthorized:
            GitHubErrorPresentation(
                title: "GitHub rejected this token.",
                detail: "Reconnect with a valid token.",
                action: nil)
        case .forbidden:
            GitHubErrorPresentation(
                title: "GitHub denied access.",
                detail: "Your token may be missing a required permission or SSO authorization.",
                action: nil)
        case .ssoRequired(let url):
            GitHubErrorPresentation(
                title: "SSO authorization required.",
                detail: "Authorize this token for the organization before retrying.",
                action: GitHubErrorAction(label: "Authorize", url: url))
        case .repoNotFound:
            GitHubErrorPresentation(
                title: "Repository unavailable.",
                detail: "Not found, or the token can't see it.",
                action: nil)
        case .rateLimited(let resetAt):
            GitHubErrorPresentation(
                title: "GitHub rate limit reached.",
                detail: "Try again after \(resetAt.formatted(date: .omitted, time: .shortened)).",
                action: nil)
        case .network(let message):
            GitHubErrorPresentation(
                title: "Network error.",
                detail: message,
                action: nil)
        case .decoding(let message):
            GitHubErrorPresentation(
                title: "Unexpected GitHub response.",
                detail: message,
                action: nil)
        case .notModified:
            GitHubErrorPresentation(
                title: "Up to date.",
                detail: "No changes were found.",
                action: nil)
        }
    }
}
