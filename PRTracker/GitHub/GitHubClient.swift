import Foundation

actor GitHubClient {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?

    init(session: URLSession, tokenProvider: @escaping @Sendable () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
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
        return r
    }

    private func send<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let req = request(url)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitHubError.network(message: error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.network(message: "non-HTTP response") }
        switch http.statusCode {
        case 200..<300:
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
