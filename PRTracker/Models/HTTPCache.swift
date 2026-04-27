import Foundation
import SwiftData

@Model
final class HTTPCache {
    @Attribute(.unique) var url: String
    var etag: String?
    var lastModified: String?
    var fetchedAt: Date

    init(url: String, etag: String? = nil, lastModified: String? = nil, fetchedAt: Date = .now) {
        self.url = url
        self.etag = etag
        self.lastModified = lastModified
        self.fetchedAt = fetchedAt
    }
}
