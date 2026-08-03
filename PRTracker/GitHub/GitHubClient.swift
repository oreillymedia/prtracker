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

    private func request(_ url: URL, conditional: Bool) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PRTracker/1.0", forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider() {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Conditional requests are opt-in: only polling endpoints send
        // If-None-Match. One-shot calls (validate/repository) must always get a
        // fresh 200 — a surprise 304 there would read as "no data".
        if conditional, let etag = etagProvider(url) {
            r.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return r
    }

    /// Variant that treats a 304 (Not Modified) as "no change" rather than an
    /// error. Returns `nil` so the caller can keep its existing stored data and
    /// skip the upsert. Conditional requests don't count against the GitHub rate
    /// limit, so this is the cheap path for steady-state polling.
    private func sendConditional<T: Decodable>(_ url: URL, as t: T.Type) async throws -> T? {
        do { return try await send(url, as: t, conditional: true) }
        catch GitHubError.notModified { return nil }
    }

    private func send<T: Decodable>(_ url: URL, as: T.Type, conditional: Bool = false) async throws -> T {
        let req = request(url, conditional: conditional)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitHubError.network(message: error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.network(message: "non-HTTP response") }
        switch http.statusCode {
        case 304: throw GitHubError.notModified
        case 200..<300:
            if conditional { etagSink(url, http.value(forHTTPHeaderField: "ETag")) }
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
            // A non-rate-limit 403 is an access problem (missing scope, org SSO
            // not authorized, unapproved fine-grained PAT) — distinct from a
            // connectivity failure, so callers can say so accurately.
            throw GitHubError.forbidden
        default: throw GitHubError.network(message: "HTTP \(http.statusCode)")
        }
    }

    func validate() async throws -> UserDTO {
        try await send(Endpoints.user, as: UserDTO.self)
    }
}

extension GitHubClient {
    // The list endpoints are conditional too: a repo with no list-level change
    // 304s, saving a full 50-item payload (and its rate-limit cost) every cycle.
    // `nil` == 304; the caller keeps the stored PR set. Because a 304 open-list
    // is NOT an authoritative "these are the only open PRs" signal, the caller
    // must not run close-reconciliation against a nil result.
    /// One page of open PRs, newest-activity first. We don't paginate, so a
    /// response of exactly `openPRPageSize` items may be truncated — see
    /// `openListIsComplete`, which the caller uses to decide whether the batch
    /// can be trusted to close the PRs it omits.
    static let openPRPageSize = 50

    func listOpenPRs(repo: RepoRef) async throws -> [PullRequestDTO]? {
        try await sendConditional(Endpoints.pulls(repo, state: "open", perPage: Self.openPRPageSize),
                                  as: [PullRequestDTO].self)
    }

    /// Whether an open-PR batch is the repo's *whole* open set. A short page is
    /// complete by definition; a full one means there may be a page 2 we never
    /// asked for, and treating it as complete would mark the stalest open PRs
    /// closed (they sort last under `updated desc` and fall off page 1).
    nonisolated static func openListIsComplete(_ dtos: [PullRequestDTO]) -> Bool {
        dtos.count < openPRPageSize
    }
    func listRecentlyMerged(repo: RepoRef, limit: Int) async throws -> [PullRequestDTO]? {
        try await sendConditional(Endpoints.pulls(repo, state: "closed", perPage: limit), as: [PullRequestDTO].self)
    }
    // Per-PR polling endpoints are conditional: they return `nil` on a 304 so
    // the caller keeps existing data. These are the calls that multiply by the
    // number of PRs every cycle, so 304s here are the bulk of the savings.
    func checkRuns(repo: RepoRef, ref: String) async throws -> CheckRunsResponseDTO? {
        try await sendConditional(Endpoints.checkRuns(repo, ref: ref), as: CheckRunsResponseDTO.self)
    }
    func participatingNotifications() async throws -> [NotificationDTO] {
        try await send(Endpoints.notificationsParticipating, as: [NotificationDTO].self)
    }
    /// Fetches a single PR's full detail, which includes diffstat fields
    /// (additions/deletions/changed_files) that are not in the list endpoint.
    func pullRequestDetail(repo: RepoRef, number: Int) async throws -> PullRequestDTO? {
        try await sendConditional(Endpoints.pullRequest(repo, number: number), as: PullRequestDTO.self)
    }
    func timeline(repo: RepoRef, number: Int) async throws -> [TimelineItemDTO]? {
        try await sendConditional(Endpoints.timeline(repo, number: number), as: [TimelineItemDTO].self)
    }
    func reviews(repo: RepoRef, number: Int) async throws -> [ReviewDTO]? {
        try await sendConditional(Endpoints.reviews(repo, number: number), as: [ReviewDTO].self)
    }
    func reviewComments(repo: RepoRef, number: Int) async throws -> [ReviewCommentDTO]? {
        try await sendConditional(Endpoints.reviewComments(repo, number: number), as: [ReviewCommentDTO].self)
    }
    func issueComments(repo: RepoRef, number: Int) async throws -> [CommentDTO] {
        try await send(Endpoints.issueComments(repo, number: number), as: [CommentDTO].self)
    }
    /// Verify a repo exists and is accessible to the token. Throws
    /// `.repoNotFound` (404) or `.unauthorized` (401) otherwise.
    func repository(_ repo: RepoRef) async throws -> RepoDTO {
        try await send(Endpoints.repo(repo), as: RepoDTO.self)
    }
}
