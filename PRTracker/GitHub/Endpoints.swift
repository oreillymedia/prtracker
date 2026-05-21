import Foundation

struct RepoRef: Equatable, Sendable {
    let owner: String
    let name: String
    var slug: String { "\(owner)/\(name)" }
}

enum Endpoints {
    static let base = URL(string: "https://api.github.com")!

    static var user: URL { base.appending(path: "/user") }

    static func pulls(_ r: RepoRef, state: String, perPage: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/pulls"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        return c.url!
    }
    static func checkRuns(_ r: RepoRef, ref: String) -> URL { base.appending(path: "/repos/\(r.slug)/commits/\(ref)/check-runs") }
    static var notificationsParticipating: URL {
        var c = URLComponents(url: base.appending(path: "/notifications"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "participating", value: "true")]
        return c.url!
    }
    static func timeline(_ r: RepoRef, number: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/issues/\(number)/timeline"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        return c.url!
    }
    static func pullRequest(_ r: RepoRef, number: Int) -> URL { base.appending(path: "/repos/\(r.slug)/pulls/\(number)") }
    static func reviews(_ r: RepoRef, number: Int) -> URL { base.appending(path: "/repos/\(r.slug)/pulls/\(number)/reviews") }
    static func reviewComments(_ r: RepoRef, number: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/pulls/\(number)/comments"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        return c.url!
    }
    static func issueComments(_ r: RepoRef, number: Int) -> URL { base.appending(path: "/repos/\(r.slug)/issues/\(number)/comments") }
    static func repo(_ r: RepoRef) -> URL { base.appending(path: "/repos/\(r.slug)") }
}
