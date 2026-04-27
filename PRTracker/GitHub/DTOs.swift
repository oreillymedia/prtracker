import Foundation

struct UserDTO: Decodable, Equatable {
    let login: String
    let name: String?
    let avatar_url: URL?
}

struct LabelDTO: Decodable, Equatable {
    let name: String
}

struct PullRequestDTO: Decodable {
    let node_id: String
    let number: Int
    let title: String
    let state: String                 // "open" | "closed"
    let draft: Bool
    let merged_at: Date?
    let created_at: Date
    let updated_at: Date
    let user: UserDTO
    let head: RefDTO
    let base: RefDTO
    let additions: Int?
    let deletions: Int?
    let changed_files: Int?
    let mergeable_state: String?
    let labels: [LabelDTO]
    let requested_reviewers: [UserDTO]?
}

struct RefDTO: Decodable {
    let ref: String
    let sha: String
}

struct CheckRunDTO: Decodable {
    let name: String
    let status: String                // "queued" | "in_progress" | "completed"
    let conclusion: String?           // "success" | "failure" | "neutral" | "cancelled" | "timed_out" | "action_required"
    let started_at: Date?
    let completed_at: Date?
}

struct CheckRunsResponseDTO: Decodable {
    let total_count: Int
    let check_runs: [CheckRunDTO]
}

struct ReviewDTO: Decodable {
    let id: Int
    let user: UserDTO
    let state: String                 // "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "PENDING"
    let body: String?
    let submitted_at: Date?
}

struct CommentDTO: Decodable {
    let id: Int
    let user: UserDTO
    let body: String
    let created_at: Date
    let updated_at: Date
}

struct TimelineItemDTO: Decodable {
    let event: String                 // "commented" | "reviewed" | "committed" | "labeled" | ...
    let id: Int?
    let node_id: String?
    let actor: UserDTO?
    let created_at: Date?
    let body: String?
    let sha: String?
    let state: String?                // for review events
}

struct NotificationDTO: Decodable {
    let id: String
    let reason: String                // "mention" | "review_requested" | "comment" | ...
    let updated_at: Date
    let subject: SubjectDTO

    struct SubjectDTO: Decodable {
        let title: String
        let url: String
        let type: String              // "PullRequest" | "Issue"
    }
}
