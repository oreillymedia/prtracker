import Foundation

enum PRState: String, Codable { case open, closed, merged, draft }
enum ReviewState: String, Codable { case pending = "PENDING", approved = "APPROVED", changesRequested = "CHANGES_REQUESTED", commented = "COMMENTED" }
enum Mergeable: String, Codable { case clean = "CLEAN", conflicts = "CONFLICTS", unknown = "UNKNOWN", blocked = "BLOCKED" }
enum CIState: String, Codable { case pass, fail, running, pending }
enum EventType: String, Codable { case commit, opened, review, comment, status, merged, closed, assigned, labeled }
