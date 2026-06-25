import Foundation
import SwiftData

/// ETag cache backing GitHub conditional requests. The `GitHubClient` consults
/// it synchronously while building a request and writes back the response ETag,
/// so reads/writes are kept in an in-memory map (guarded by a lock) and mirrored
/// to the `HTTPCache` store on a background task. Persisting means the first poll
/// after launch can already send `If-None-Match` and get a free 304.
///
/// Note: the ETag is recorded as soon as a 200 decodes, before the caller upserts
/// the data. If that upsert later fails, the ETag is briefly "ahead" of the
/// stored data and the next poll 304s — but the next genuine change yields a new
/// ETag and self-heals. Acceptable given how rarely a local SwiftData save fails.
final class ETagStore: @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        hydrate()
    }

    private func hydrate() {
        let ctx = ModelContext(modelContainer)
        let rows = (try? ctx.fetch(FetchDescriptor<HTTPCache>())) ?? []
        lock.lock(); defer { lock.unlock() }
        for row in rows {
            if let etag = row.etag { cache[row.url] = etag }
        }
    }

    func etag(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[url.absoluteString]
    }

    func setEtag(_ etag: String?, for url: URL) {
        let key = url.absoluteString
        lock.lock()
        if let etag { cache[key] = etag } else { cache.removeValue(forKey: key) }
        lock.unlock()
        persist(etag: etag, url: key)
    }

    private func persist(etag: String?, url: String) {
        let container = modelContainer
        Task.detached {
            let ctx = ModelContext(container)
            let target = url
            let existing = (try? ctx.fetch(FetchDescriptor<HTTPCache>(predicate: #Predicate { $0.url == target })))?.first
            if let existing {
                existing.etag = etag
                existing.fetchedAt = .now
            } else if let etag {
                ctx.insert(HTTPCache(url: url, etag: etag))
            }
            try? ctx.save()
        }
    }
}
