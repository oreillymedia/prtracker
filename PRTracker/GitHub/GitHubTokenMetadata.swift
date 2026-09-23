import Foundation

enum GitHubTokenType: String, Equatable, Sendable {
    case classic
    case fineGrained
    case other
}

struct GitHubTokenMetadata: Equatable, Sendable {
    let type: GitHubTokenType
    let scopes: [String]
    let expiration: Date?

    init(token: String, headers: [String: String]) {
        let trimmed = Self.normalizedToken(token)
        if trimmed.hasPrefix("ghp_") {
            type = .classic
        } else if trimmed.hasPrefix("github_pat_") {
            type = .fineGrained
        } else {
            type = .other
        }

        scopes = Self.header("X-OAuth-Scopes", in: headers)?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        expiration = Self.parseExpiration(Self.header("GitHub-Authentication-Token-Expiration", in: headers))
    }

    static func normalizedToken(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasPartialSSO(in headers: [String: String]) -> Bool {
        header("X-GitHub-SSO", in: headers)?.lowercased().hasPrefix("partial-results") == true
    }

    private static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func parseExpiration(_ raw: String?) -> Date? {
        guard let raw else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        if let date = formatter.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        return iso.date(from: raw)
    }
}

enum GitHubTokenGuide {
    static let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=PRTracker")!

    static let checklist = [
        "Click Create a token on GitHub.",
        "Expiration: choose No expiration. Any shorter choice works; PR Tracker will warn a week before it lapses.",
        "Click Generate token, copy it, and paste it below.",
        "On the token's row click Configure SSO → Authorize for oreillymedia.",
    ]

    static let fineGrainedNote = "Fine-grained tokens also work: resource owner oreillymedia, the repositories you'll track, permissions Pull requests: Read and Checks: Read."
}
