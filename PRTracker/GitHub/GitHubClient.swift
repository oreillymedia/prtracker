import Foundation

actor GitHubClient {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let etagProvider: @Sendable (URL) -> String?
    private let etagSink: @Sendable (URL, String?) -> Void

    init(session: URLSession, tokenProvider: @escaping @Sendable () -> String?, etagProvider: @escaping @Sendable (URL) -> String? = { _ in nil }, etagSink: @escaping @Sendable (URL, String?) -> Void = { _, _ in }) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.etagProvider = etagProvider
        self.etagSink = etagSink
    }

    private static let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PRTracker/1.0", forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider() {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag = etagProvider(url) {
            r.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return r
    }

    private func send<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let req = request(url)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitHubError.network(message: error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.network(message: "non-HTTP response") }
        switch http.statusCode {
        case 304: throw GitHubError.notModified
        case 200..<300:
            etagSink(url, http.value(forHTTPHeaderField: "ETag"))
            do { return try Self.isoDecoder.decode(T.self, from: data) }
            catch { throw GitHubError.decoding(message: String(describing: error)) }
        case 401: throw GitHubError.unauthorized
        case 404: throw GitHubError.repoNotFound
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let resetStr = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetEpoch = TimeInterval(resetStr) {
                throw GitHubError.rateLimited(resetAt: Date(timeIntervalSince1970: resetEpoch))
            }
            throw GitHubError.network(message: "403 forbidden")
        default: throw GitHubError.network(message: "HTTP \(http.statusCode)")
        }
    }

    func validate() async throws -> UserDTO {
        try await send(Endpoints.user, as: UserDTO.self)
    }
}

extension GitHubClient {
    func listOpenPRs(repo: RepoRef) async throws -> [PullRequestDTO] {
        try await send(Endpoints.pulls(repo, state: "open", perPage: 50), as: [PullRequestDTO].self)
    }
    func listRecentlyMerged(repo: RepoRef, limit: Int) async throws -> [PullRequestDTO] {
        try await send(Endpoints.pulls(repo, state: "closed", perPage: limit), as: [PullRequestDTO].self)
    }
    func checkRuns(repo: RepoRef, ref: String) async throws -> CheckRunsResponseDTO {
        try await send(Endpoints.checkRuns(repo, ref: ref), as: CheckRunsResponseDTO.self)
    }
    func participatingNotifications() async throws -> [NotificationDTO] {
        try await send(Endpoints.notificationsParticipating, as: [NotificationDTO].self)
    }
    /// Fetches a single PR's full detail, which includes diffstat fields
    /// (additions/deletions/changed_files) that are not in the list endpoint.
    func pullRequestDetail(repo: RepoRef, number: Int) async throws -> PullRequestDTO {
        try await send(Endpoints.pullRequest(repo, number: number), as: PullRequestDTO.self)
    }
    func timeline(repo: RepoRef, number: Int) async throws -> [TimelineItemDTO] {
        try await send(Endpoints.timeline(repo, number: number), as: [TimelineItemDTO].self)
    }
    func reviews(repo: RepoRef, number: Int) async throws -> [ReviewDTO] {
        try await send(Endpoints.reviews(repo, number: number), as: [ReviewDTO].self)
    }
    func reviewComments(repo: RepoRef, number: Int) async throws -> [ReviewCommentDTO] {
        try await send(Endpoints.reviewComments(repo, number: number), as: [ReviewCommentDTO].self)
    }
    func issueComments(repo: RepoRef, number: Int) async throws -> [CommentDTO] {
        try await send(Endpoints.issueComments(repo, number: number), as: [CommentDTO].self)
    }
}
