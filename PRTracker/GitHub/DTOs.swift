import Foundation

nonisolated struct UserDTO: Decodable, Equatable {
    let login: String
    let name: String?
    let avatar_url: URL?
}

nonisolated struct LabelDTO: Decodable, Equatable {
    let name: String
}

nonisolated struct PullRequestDTO: Decodable {
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

nonisolated struct RefDTO: Decodable {
    let ref: String
    let sha: String
}

nonisolated struct CheckRunDTO: Decodable {
    let id: Int
    let name: String
    let status: String                // "queued" | "in_progress" | "completed"
    let conclusion: String?           // "success" | "failure" | "neutral" | "cancelled" | "timed_out" | "action_required"
    let started_at: Date?
    let completed_at: Date?
}

nonisolated struct CheckRunsResponseDTO: Decodable {
    let total_count: Int
    let check_runs: [CheckRunDTO]
}

nonisolated struct ReviewDTO: Decodable {
    let id: Int
    let user: UserDTO
    let state: String                 // "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "PENDING"
    let body: String?
    let submitted_at: Date?
}

nonisolated struct CommentDTO: Decodable {
    let id: Int
    let user: UserDTO
    let body: String
    let created_at: Date
    let updated_at: Date
}

nonisolated struct ReviewCommentDTO: Decodable {
    let id: Int
    let node_id: String?
    let pull_request_review_id: Int?
    let in_reply_to_id: Int?
    let user: UserDTO
    let body: String
    let path: String
    let line: Int?
    let original_line: Int?
    let diff_hunk: String
    let created_at: Date
    let updated_at: Date
}

nonisolated struct TimelineItemDTO: Decodable {
    let event: String                 // "commented" | "reviewed" | "committed" | "labeled" | ...
    let id: Int?
    let node_id: String?
    let actor: UserDTO?
    let created_at: Date?
    let body: String?
    let sha: String?
    let state: String?                // for review events
    let submitted_at: Date?           // present on "reviewed" events
    let author: GitAuthorDTO?         // present on "committed" events
    let committer: GitAuthorDTO?      // present on "committed" events
    let user: UserDTO?                // present on "reviewed" events instead of `actor`
    let message: String?              // commit message on "committed" events

    init(event: String, id: Int? = nil, node_id: String? = nil, actor: UserDTO? = nil,
         created_at: Date? = nil, body: String? = nil, sha: String? = nil, state: String? = nil,
         submitted_at: Date? = nil, author: GitAuthorDTO? = nil,
         committer: GitAuthorDTO? = nil, user: UserDTO? = nil,
         message: String? = nil) {
        self.event = event
        self.id = id
        self.node_id = node_id
        self.actor = actor
        self.created_at = created_at
        self.body = body
        self.sha = sha
        self.state = state
        self.submitted_at = submitted_at
        self.author = author
        self.committer = committer
        self.user = user
        self.message = message
    }

    /// The effective timestamp for this event, regardless of which field GitHub
    /// chose to put it in for the event type.
    var effectiveDate: Date? {
        created_at
            ?? submitted_at
            ?? committer?.date
            ?? author?.date
    }

    /// The effective acting user, regardless of which field GitHub used.
    var effectiveActor: UserDTO? {
        actor ?? user
    }
}

nonisolated struct GitAuthorDTO: Decodable, Equatable {
    let name: String?
    let email: String?
    let date: Date?
}

nonisolated struct NotificationDTO: Decodable {
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

nonisolated struct RepoDTO: Decodable, Equatable {
    let full_name: String
}
