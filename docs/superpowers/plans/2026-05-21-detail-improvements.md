# Detail-View Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-line review comments + threaded replies to the PR detail timeline, and render comment / review bodies as inline markdown using `AttributedString(markdown:)`.

**Architecture:** A new `ReviewComment` `@Model` is fetched from `GET /pulls/{n}/comments` alongside the existing detail-load endpoints, threaded by `inReplyToID`, and matched to its parent review via the integer `pull_request_review_id`. A small `MarkdownText` helper replaces plain `Text(body)` calls in two render sites. Nested `ReviewCommentThreadView`s slot into each parent review event card.

**Tech Stack:** SwiftUI on macOS 26, SwiftData persistence, Swift Testing (`@Suite`/`@Test`/`#expect`), existing `StubURLProtocol` for GitHub client tests.

**Spec reference:** `docs/superpowers/specs/2026-05-21-detail-improvements-design.md`
**Branch:** `detail-improvments` (already checked out)

---

## File Structure

### Create

- `PRTracker/GitHub/DTOs.swift` (additive) — `ReviewCommentDTO`
- `PRTracker/GitHub/Endpoints.swift` (additive) — `reviewComments(_:, number:)`
- `PRTracker/GitHub/GitHubClient.swift` (additive) — `reviewComments(repo:, number:)`
- `PRTracker/Models/ReviewComment.swift` — new `@Model`
- `PRTracker/DesignSystem/MarkdownText.swift` — markdown helper view
- `PRTracker/Views/Detail/ReviewCommentCard.swift` — single-comment card
- `PRTracker/Views/Detail/ReviewCommentThreadView.swift` — root + indented replies
- `PRTrackerTests/GitHub/Fixtures/pulls_5107_comments.json` — fixture
- `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift` — actor tests
- `PRTrackerTests/GitHub/ReviewCommentDecodingTests.swift` — DTO decoding tests

### Modify

- `PRTracker/Models/TimelineEvent.swift` — add `var reviewID: Int?`
- `PRTracker/Models/PullRequest.swift` — add `@Relationship reviewComments: [ReviewComment]`
- `PRTracker/Sync/SyncActor.swift`:
  - `upsertTimeline` — set `event.reviewID` for `event.type == .review`
  - `setSeenForPR` — cascade to `pr.reviewComments`
  - `setSeenUpTo` — cascade to comments whose parent review is at-or-before target.at
  - Add `upsertReviewComments(prID:, fromDTOs:)`
  - Add `setSeen(reviewCommentID:, isSeen:)`
- `PRTracker/Views/Detail/TimelineEventRow.swift` — body uses `MarkdownText`; review events render a nested `VStack` of `ReviewCommentThreadView`s
- `PRTracker/Views/Detail/PRDetailView.swift` — `loadTimeline()` fetches `/comments` and calls `upsertReviewComments`

### Delete

None.

---

## Task 1: Add `TimelineEvent.reviewID` + populate during `upsertTimeline`

**Files:**
- Modify: `PRTracker/Models/TimelineEvent.swift`
- Modify: `PRTracker/Sync/SyncActor.swift`

This is the foundation for the parent-review matching key. Adding it before the new model means later tasks have something to point at.

- [ ] **Step 1: Add the field to `TimelineEvent`**

Open `PRTracker/Models/TimelineEvent.swift`. After the existing `var sha: String?` line, add:

```swift
    var sha: String?
    var reviewID: Int?
    var reviewStateRaw: String?
```

(Position between `sha` and `reviewStateRaw`. SwiftData treats this as an additive migration — existing rows get `nil`.)

- [ ] **Step 2: Populate `reviewID` in `upsertTimeline`**

Open `PRTracker/Sync/SyncActor.swift`. Find the `upsertTimeline(prID:items:)` method (around line 146). Inside the per-DTO loop, after the existing `let typ: EventType = { ... }()` block, add:

```swift
            let parentReviewID: Int? = (typ == .review) ? dto.id : nil
```

Then inside both branches of `if let e = byID[id] { ... } else { ... }`, set the `reviewID` field:

- In the update branch (after `e.reviewState = revState ?? e.reviewState`):
  ```swift
                e.reviewID = parentReviewID ?? e.reviewID
  ```

- In the insert branch, replace the existing `TimelineEvent(...)` initializer call with:
  ```swift
                let e = TimelineEvent(
                    id: id, type: typ, at: effectiveAt ?? .now,
                    pullRequest: pr, actor: actorUser,
                    body: effectiveBody, sha: dto.sha, reviewState: revState, isSeen: false)
                e.reviewID = parentReviewID
                ctx.insert(e)
  ```

(`init` stays unchanged; we set the property after insertion.)

- [ ] **Step 3: Verify the project builds**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Models/TimelineEvent.swift PRTracker/Sync/SyncActor.swift
git commit -m "feat(model): add TimelineEvent.reviewID for review-comment parent matching"
```

---

## Task 2: Add `ReviewCommentDTO` + endpoint + client method + decoding test

**Files:**
- Modify: `PRTracker/GitHub/DTOs.swift`
- Modify: `PRTracker/GitHub/Endpoints.swift`
- Modify: `PRTracker/GitHub/GitHubClient.swift`
- Create: `PRTrackerTests/GitHub/Fixtures/pulls_5107_comments.json`
- Create: `PRTrackerTests/GitHub/ReviewCommentDecodingTests.swift`

- [ ] **Step 1: Add the DTO**

Open `PRTracker/GitHub/DTOs.swift`. After the existing `struct CommentDTO` block (around line 65), insert:

```swift
struct ReviewCommentDTO: Decodable {
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
```

- [ ] **Step 2: Add the endpoint URL builder**

Open `PRTracker/GitHub/Endpoints.swift`. After the existing `reviews(...)` static, add:

```swift
    static func reviewComments(_ r: RepoRef, number: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/pulls/\(number)/comments"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        return c.url!
    }
```

- [ ] **Step 3: Add the client method**

Open `PRTracker/GitHub/GitHubClient.swift`. After the existing `reviews(repo:number:)` method (around line 87), add:

```swift
    func reviewComments(repo: RepoRef, number: Int) async throws -> [ReviewCommentDTO] {
        try await send(Endpoints.reviewComments(repo, number: number), as: [ReviewCommentDTO].self)
    }
```

- [ ] **Step 4: Create the fixture**

Create `PRTrackerTests/GitHub/Fixtures/pulls_5107_comments.json` with three comments — two roots (one with a diff_hunk and a line; one outdated using `original_line`) and one reply to the first root:

```json
[
  {
    "id": 1001,
    "node_id": "PRRC_1001",
    "pull_request_review_id": 9001,
    "in_reply_to_id": null,
    "user": {"login": "alex.chen", "node_id": "U_alex"},
    "body": "Should we cache this?",
    "path": "Sources/Player.swift",
    "line": 42,
    "original_line": 42,
    "diff_hunk": "@@ -38,7 +38,9 @@\n func play() {\n+    let cache = CacheStore.shared\n+    cache.warm(for: media)\n     let player = AVPlayer()\n     player.play()\n }",
    "created_at": "2026-05-19T15:00:00Z",
    "updated_at": "2026-05-19T15:00:00Z"
  },
  {
    "id": 1002,
    "node_id": "PRRC_1002",
    "pull_request_review_id": 9001,
    "in_reply_to_id": 1001,
    "user": {"login": "jamie.r", "node_id": "U_jamie"},
    "body": "Good idea. Will follow up.",
    "path": "Sources/Player.swift",
    "line": 42,
    "original_line": 42,
    "diff_hunk": "@@ -38,7 +38,9 @@\n func play() {\n+    let cache = CacheStore.shared\n+    cache.warm(for: media)\n     let player = AVPlayer()\n     player.play()\n }",
    "created_at": "2026-05-19T15:05:00Z",
    "updated_at": "2026-05-19T15:05:00Z"
  },
  {
    "id": 1003,
    "node_id": "PRRC_1003",
    "pull_request_review_id": 9001,
    "in_reply_to_id": null,
    "user": {"login": "alex.chen", "node_id": "U_alex"},
    "body": "This line moved; flagged as outdated.",
    "path": "Sources/Reader.swift",
    "line": null,
    "original_line": 17,
    "diff_hunk": "@@ -15,5 +15,5 @@\n class Reader {\n-    var page: Int = 0\n+    var page: Int = 1\n     func next() {}\n }",
    "created_at": "2026-05-19T15:10:00Z",
    "updated_at": "2026-05-19T15:10:00Z"
  }
]
```

- [ ] **Step 5: Write the decoding test**

Create `PRTrackerTests/GitHub/ReviewCommentDecodingTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct ReviewCommentDecodingTests {
    private func loadFixture() throws -> Data {
        let url = Bundle(for: BundleAnchor.self)
            .url(forResource: "pulls_5107_comments", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    @Test func decodesArrayOfThree() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        #expect(comments.count == 3)
    }

    @Test func decodesReplyLink() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        let reply = comments.first(where: { $0.id == 1002 })
        #expect(reply?.in_reply_to_id == 1001)
    }

    @Test func decodesOutdatedComment() throws {
        let data = try loadFixture()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewCommentDTO].self, from: data)
        let outdated = comments.first(where: { $0.id == 1003 })
        #expect(outdated?.line == nil)
        #expect(outdated?.original_line == 17)
    }
}
```

If `BundleAnchor` doesn't exist in the test target, look at how `pulls_5107_comments` is loaded by reading the existing `GitHubClientTests.swift`'s `loadFixture` helper (the test target already has a fixture-loading pattern) and adapt the test to match. Inspect with:
```bash
grep -n "loadFixture\|Bundle\|BundleAnchor" /Users/mblackmon/code/PRTracker/PRTrackerTests/GitHub/GitHubClientTests.swift /Users/mblackmon/code/PRTracker/PRTrackerTests/GitHub/StubURLProtocol.swift
```

- [ ] **Step 6: Run the new tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/ReviewCommentDecodingTests 2>&1 | tail -10
```
Expected: 3 tests pass.

- [ ] **Step 7: Run the full suite to confirm no regressions**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/GitHub/DTOs.swift PRTracker/GitHub/Endpoints.swift PRTracker/GitHub/GitHubClient.swift PRTrackerTests/GitHub/Fixtures/pulls_5107_comments.json PRTrackerTests/GitHub/ReviewCommentDecodingTests.swift
git commit -m "feat(github): ReviewCommentDTO + /pulls/{n}/comments endpoint + decoding tests"
```

---

## Task 3: Create `ReviewComment` `@Model` + relationship on `PullRequest`

**Files:**
- Create: `PRTracker/Models/ReviewComment.swift`
- Modify: `PRTracker/Models/PullRequest.swift`
- Modify: `PRTracker/App/PRTrackerApp.swift` — register the new model in the SwiftData schema

- [ ] **Step 1: Create the model**

Create `PRTracker/Models/ReviewComment.swift`:

```swift
import Foundation
import SwiftData

@Model
final class ReviewComment {
    @Attribute(.unique) var id: String   // "RC_<github-id>" surrogate
    var parentReviewIntegerID: Int?
    var inReplyToID: String?
    var author: User
    var body: String
    var path: String
    var line: Int?
    var diffHunk: String
    var createdAt: Date
    /// Local-only — never overwritten by sync.
    var isSeen: Bool
    var pullRequest: PullRequest

    init(id: String, parentReviewIntegerID: Int?, inReplyToID: String?, author: User,
         body: String, path: String, line: Int?, diffHunk: String, createdAt: Date,
         isSeen: Bool = false, pullRequest: PullRequest) {
        self.id = id
        self.parentReviewIntegerID = parentReviewIntegerID
        self.inReplyToID = inReplyToID
        self.author = author
        self.body = body
        self.path = path
        self.line = line
        self.diffHunk = diffHunk
        self.createdAt = createdAt
        self.isSeen = isSeen
        self.pullRequest = pullRequest
    }
}
```

- [ ] **Step 2: Add the relationship on `PullRequest`**

Open `PRTracker/Models/PullRequest.swift`. After the existing `@Relationship(deleteRule: .cascade, inverse: \CIRun.pr) var ciChecks: [CIRun] = []` block, add:

```swift
    @Relationship(deleteRule: .cascade, inverse: \ReviewComment.pullRequest)
    var reviewComments: [ReviewComment] = []
```

- [ ] **Step 3: Register the model in the SwiftData schema**

Open `PRTracker/App/PRTrackerApp.swift`. Find the `Schema([...])` initializer (in `init()`). Add `ReviewComment.self` to the array:

```swift
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
            ReviewComment.self,
        ])
```

- [ ] **Step 4: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: both succeed.

- [ ] **Step 5: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Models/ReviewComment.swift PRTracker/Models/PullRequest.swift PRTracker/App/PRTrackerApp.swift
git commit -m "feat(model): ReviewComment @Model + PullRequest relationship + schema registration"
```

---

## Task 4: `SyncActor.upsertReviewComments(prID:, fromDTOs:)` + tests

**Files:**
- Modify: `PRTracker/Sync/SyncActor.swift`
- Create: `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct SyncActorReviewCommentsTests {
    private func setup() throws -> (ModelContainer, Repo, PullRequest) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let user = User(login: "alex.chen", name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(user); ctx.insert(repo)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let pr = PullRequest(id: "PR_5107", number: 5107, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: t, updatedAt: t, author: user, repo: repo)
        ctx.insert(pr)
        try ctx.save()
        return (container, repo, pr)
    }

    private func sampleDTO(id: Int = 1001, reviewID: Int? = 9001, replyTo: Int? = nil,
                           body: String = "Body", line: Int? = 42, origLine: Int? = 42) -> ReviewCommentDTO {
        let json = """
        {"id":\(id),"node_id":"PRRC_\(id)","pull_request_review_id":\(reviewID.map(String.init) ?? "null"),
         "in_reply_to_id":\(replyTo.map(String.init) ?? "null"),
         "user":{"login":"alex.chen","node_id":"U_alex"},
         "body":"\(body)","path":"Sources/Player.swift",
         "line":\(line.map(String.init) ?? "null"),"original_line":\(origLine.map(String.init) ?? "null"),
         "diff_hunk":"@@ ...\\n func play(){}",
         "created_at":"2026-05-19T15:00:00Z","updated_at":"2026-05-19T15:00:00Z"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(ReviewCommentDTO.self, from: json.data(using: .utf8)!)
    }

    @Test func upsertInsertsNew() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO()])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.count == 1)
        #expect(comments[0].id == "RC_1001")
        #expect(comments[0].parentReviewIntegerID == 9001)
        #expect(comments[0].line == 42)
    }

    @Test func upsertUpdatesExistingByID() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Original")])
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Edited")])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.count == 1)
        #expect(comments[0].body == "Edited")
    }

    @Test func upsertPreservesIsSeen() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO()])
        let ctx = ModelContext(container)
        let c = try ctx.fetch(FetchDescriptor<ReviewComment>()).first!
        c.isSeen = true
        try ctx.save()
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(body: "Edited")])
        let ctx2 = ModelContext(container)
        let c2 = try ctx2.fetch(FetchDescriptor<ReviewComment>()).first!
        #expect(c2.isSeen == true)
    }

    @Test func upsertPurgesStale() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002)])
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO(id: 1001)])
        let ctx = ModelContext(container)
        let ids = try ctx.fetch(FetchDescriptor<ReviewComment>()).map(\.id)
        #expect(ids == ["RC_1001"])
    }

    @Test func upsertFallsBackToOriginalLineWhenLineNil() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(line: nil, origLine: 17)])
        let ctx = ModelContext(container)
        let c = try ctx.fetch(FetchDescriptor<ReviewComment>()).first!
        #expect(c.line == 17)
    }

    @Test func upsertSetsInReplyToID() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002, replyTo: 1001)])
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>()).sorted { $0.id < $1.id }
        #expect(comments[0].inReplyToID == nil)
        #expect(comments[1].inReplyToID == "RC_1001")
    }
}
```

- [ ] **Step 2: Verify the tests fail to compile**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "cannot find 'upsertReviewComments'" | head -3
```
Expected: errors about the missing method.

- [ ] **Step 3: Implement `upsertReviewComments`**

Open `PRTracker/Sync/SyncActor.swift`. After the `upsertCIChecks` method (around line 100), add:

```swift
    /// Upsert per-line review comments fetched from /pulls/{n}/comments.
    /// `id` surrogate is `node_id` if present, else "RC_<integer>". Existing
    /// rows have their body/path/line/diffHunk refreshed; `isSeen` is preserved.
    /// Anything previously stored for this PR that isn't in the response is
    /// purged.
    func upsertReviewComments(prID: String, fromDTOs comments: [ReviewCommentDTO]) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }

        var byID: [String: ReviewComment] = [:]
        for c in pr.reviewComments { byID[c.id] = c }

        var seenIDs: Set<String> = []
        for dto in comments {
            let cid = dto.node_id ?? "RC_\(dto.id)"
            seenIDs.insert(cid)
            let resolvedLine = dto.line ?? dto.original_line
            let replyTo = dto.in_reply_to_id.map { "RC_\($0)" }

            if let existing = byID[cid] {
                existing.body = dto.body
                existing.path = dto.path
                existing.line = resolvedLine
                existing.diffHunk = dto.diff_hunk
                existing.parentReviewIntegerID = dto.pull_request_review_id
                existing.inReplyToID = replyTo
                // isSeen and createdAt preserved deliberately.
            } else {
                let author = upsertUser(dto.user, ctx: ctx)
                let comment = ReviewComment(
                    id: cid,
                    parentReviewIntegerID: dto.pull_request_review_id,
                    inReplyToID: replyTo,
                    author: author,
                    body: dto.body,
                    path: dto.path,
                    line: resolvedLine,
                    diffHunk: dto.diff_hunk,
                    createdAt: dto.created_at,
                    isSeen: false,
                    pullRequest: pr)
                ctx.insert(comment)
            }
        }
        for c in pr.reviewComments where !seenIDs.contains(c.id) {
            ctx.delete(c)
        }
        try ctx.save()
    }
```

The `upsertUser(_:ctx:)` helper already exists at the top of the actor. The `prByID(_:ctx:)` helper also already exists.

- [ ] **Step 4: Run the new tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SyncActorReviewCommentsTests 2>&1 | tail -15
```
Expected: All 6 tests pass.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Sync/SyncActor.swift PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift
git commit -m "feat(sync): upsertReviewComments — insert/update/purge with isSeen preserved"
```

---

## Task 5: isSeen cascade — `setSeenForPR`, `setSeenUpTo`, and per-comment toggle

**Files:**
- Modify: `PRTracker/Sync/SyncActor.swift`
- Modify: `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`

- [ ] **Step 1: Append failing tests**

Open `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`. Before the closing `}` of the `@Suite`, append:

```swift
    @Test func setSeenForPRCascadesToReviewComments() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002)])
        try await actor.setSeenForPR(prID: "PR_5107", isSeen: true)
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.allSatisfy(\.isSeen))
    }

    @Test func setSeenForPRUnsets() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107", fromDTOs: [sampleDTO()])
        try await actor.setSeenForPR(prID: "PR_5107", isSeen: true)
        try await actor.setSeenForPR(prID: "PR_5107", isSeen: false)
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>())
        #expect(comments.allSatisfy { $0.isSeen == false })
    }

    @Test func setSeenForSingleReviewComment() async throws {
        let (container, _, _) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertReviewComments(prID: "PR_5107",
            fromDTOs: [sampleDTO(id: 1001), sampleDTO(id: 1002)])
        try await actor.setSeen(reviewCommentID: "RC_1001", isSeen: true)
        let ctx = ModelContext(container)
        let comments = try ctx.fetch(FetchDescriptor<ReviewComment>()).sorted { $0.id < $1.id }
        #expect(comments[0].isSeen == true)
        #expect(comments[1].isSeen == false)
    }
```

- [ ] **Step 2: Extend `setSeenForPR`**

Open `PRTracker/Sync/SyncActor.swift`. Find `setSeenForPR(prID:isSeen:)` (around line 210). After the existing `for e in pr.timeline { e.isSeen = isSeen }` line, add:

```swift
        for c in pr.reviewComments { c.isSeen = isSeen }
```

- [ ] **Step 3: Extend `setSeenUpTo`**

In the same file, find `setSeenUpTo(prID:throughEventID:)` (around line 217). After the existing `for e in pr.timeline where e.at <= target.at { e.isSeen = true }` line, add a cascade for review comments whose parent review event is at-or-before the target:

```swift
        // Cascade to review comments whose parent review event is at-or-before
        // the target's timestamp. We look the parent reviews up by reviewID.
        let cutoffReviewIDs = Set(
            pr.timeline
                .filter { $0.at <= target.at && $0.type == .review }
                .compactMap(\.reviewID)
        )
        for c in pr.reviewComments where c.parentReviewIntegerID.map(cutoffReviewIDs.contains) == true {
            c.isSeen = true
        }
```

- [ ] **Step 4: Add `setSeen(reviewCommentID:, isSeen:)`**

In the same file, after the `setLastReadAt(prID:date:)` method, before the actor's closing `}`, add:

```swift
    func setSeen(reviewCommentID: String, isSeen: Bool) throws {
        let ctx = modelContext
        let target = reviewCommentID
        let predicate = #Predicate<ReviewComment> { $0.id == target }
        guard let c = try ctx.fetch(FetchDescriptor<ReviewComment>(predicate: predicate)).first else { return }
        c.isSeen = isSeen
        try ctx.save()
    }
```

- [ ] **Step 5: Run the new tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SyncActorReviewCommentsTests 2>&1 | tail -15
```
Expected: All 9 tests in the suite pass.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Sync/SyncActor.swift PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift
git commit -m "feat(sync): isSeen cascade for review comments + per-comment toggle"
```

---

## Task 6: Wire `loadTimeline` to fetch + upsert review comments

**Files:**
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`

- [ ] **Step 1: Add the 6th parallel fetch**

Open `PRTracker/Views/Detail/PRDetailView.swift`. Find the existing `do { async let t = ... }` block inside `loadTimeline()`. Replace it with:

```swift
        do {
            async let t = client.timeline(repo: ref, number: number)
            async let r = client.reviews(repo: ref, number: number)
            async let c = client.issueComments(repo: ref, number: number)
            async let d = client.pullRequestDetail(repo: ref, number: number)
            async let ck = client.checkRuns(repo: ref, ref: headSha)
            async let rc = client.reviewComments(repo: ref, number: number)
            let (tItems, reviewDTOs, _, detail, checks, reviewComments) = try await (t, r, c, d, ck, rc)
            try await syncActor.upsertTimeline(prID: prID, items: tItems)
            try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs)
            try await syncActor.upsertReviewComments(prID: prID, fromDTOs: reviewComments)
            try await syncActor.updatePRStatistics(prID: prID, dto: detail)
            try await syncActor.upsertCIChecks(prID: prID, dto: checks)
            loadError = nil
```

`upsertReviewComments` must run *after* `upsertTimeline` so the parent review's `reviewID` is populated before comments look up their host card.

- [ ] **Step 2: Build + test**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: both succeed.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/PRDetailView.swift
git commit -m "feat(detail): fetch /pulls/{n}/comments alongside timeline on detail open"
```

---

## Task 7: `MarkdownText` helper + apply to existing comment / review bodies

**Files:**
- Create: `PRTracker/DesignSystem/MarkdownText.swift`
- Modify: `PRTracker/Views/Detail/TimelineEventRow.swift`

- [ ] **Step 1: Create the helper**

Create `PRTracker/DesignSystem/MarkdownText.swift`:

```swift
import SwiftUI

/// Renders a comment body using SwiftUI's built-in markdown parsing.
/// Inline elements (bold, italic, links, inline code, strikethrough) parse.
/// Block elements (headings, lists, fenced code blocks) render as literal
/// markdown text — accepted per the design directive.
struct MarkdownText: View {
    let raw: String

    var body: some View {
        Text(attributed)
            .font(.system(size: 13))
            .foregroundStyle(Tokens.text)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts))
            ?? AttributedString(raw)
    }
}
```

- [ ] **Step 2: Apply to `TimelineEventRow.cardContent`**

Open `PRTracker/Views/Detail/TimelineEventRow.swift`. Find the `cardContent` computed property. Inside it, find the block that renders the body:

```swift
            if let body = event.body {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
            }
```

Replace with:

```swift
            if let body = event.body, !body.isEmpty {
                MarkdownText(raw: body)
            }
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the test suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Manually verify**

Run the app, open a PR with a review body that contains inline markdown (bold/italic/links/inline code). Confirm:
- Bold renders bold.
- Italic renders italic.
- Inline code renders monospaced.
- Links render with the accent color (default Text + AttributedString behavior).
- Fenced code blocks (` ``` `) and headings still appear as raw text — known limitation.

- [ ] **Step 6: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/DesignSystem/MarkdownText.swift PRTracker/Views/Detail/TimelineEventRow.swift
git commit -m "feat(detail): MarkdownText helper + apply to timeline review/comment bodies"
```

---

## Task 8: `ReviewCommentCard` view

**Files:**
- Create: `PRTracker/Views/Detail/ReviewCommentCard.swift`

- [ ] **Step 1: Create the card**

Create `PRTracker/Views/Detail/ReviewCommentCard.swift`:

```swift
import SwiftUI

struct ReviewCommentCard: View {
    let comment: ReviewComment
    let showsAnchor: Bool   // false for replies; they inherit the root's path:line + diff_hunk
    var onToggleSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsAnchor {
                breadcrumb
                diffHunkBlock
            }
            authorRow
            MarkdownText(raw: comment.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
        .opacity(comment.isSeen ? 0.48 : 1)
        .contextMenu {
            Button(comment.isSeen ? "Mark unseen" : "Mark seen", action: onToggleSeen)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 0) {
            Text(comment.path).font(.system(size: 10.5).monospaced())
            if let line = comment.line {
                Text(":\(line)").font(.system(size: 10.5).monospaced())
            }
        }
        .foregroundStyle(Tokens.textFaint)
    }

    private var diffHunkBlock: some View {
        Text(comment.diffHunk)
            .font(.system(size: 11).monospaced())
            .foregroundStyle(Tokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            AvatarView(user: comment.author, size: 18)
            Text(comment.author.name ?? comment.author.login)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.text)
            Spacer()
            Text(RelativeTimeFormatter.short(comment.createdAt))
                .font(.system(size: 10.5))
                .foregroundStyle(Tokens.textFaint)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

(No call sites yet — Task 10 wires it in. Build verifies the file compiles in isolation.)

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ReviewCommentCard.swift
git commit -m "feat(detail): ReviewCommentCard view (breadcrumb + diff_hunk + author + markdown body)"
```

---

## Task 9: `ReviewCommentThreadView` (root + indented replies)

**Files:**
- Create: `PRTracker/Views/Detail/ReviewCommentThreadView.swift`

- [ ] **Step 1: Create the thread view**

Create `PRTracker/Views/Detail/ReviewCommentThreadView.swift`:

```swift
import SwiftUI

struct ReviewCommentThreadView: View {
    let root: ReviewComment
    let replies: [ReviewComment]   // pre-filtered & pre-sorted by caller
    let syncActor: SyncActor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewCommentCard(comment: root, showsAnchor: true,
                onToggleSeen: { toggleSeen(root) })

            if !replies.isEmpty {
                ZStack(alignment: .leading) {
                    // Hairline rail behind the indented reply stack.
                    Rectangle()
                        .fill(Tokens.hairline)
                        .frame(width: 1)
                        .padding(.leading, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(replies) { reply in
                            ReviewCommentCard(comment: reply, showsAnchor: false,
                                onToggleSeen: { toggleSeen(reply) })
                        }
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }

    private func toggleSeen(_ c: ReviewComment) {
        let id = c.id
        let wasSeen = c.isSeen
        Task { try? await syncActor.setSeen(reviewCommentID: id, isSeen: !wasSeen) }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ReviewCommentThreadView.swift
git commit -m "feat(detail): ReviewCommentThreadView with indented replies + hairline rail"
```

---

## Task 10: Wire nested threads into `TimelineEventRow` for review events

**Files:**
- Modify: `PRTracker/Views/Detail/TimelineEventRow.swift`
- Modify: `PRTracker/Views/Detail/TimelineColumn.swift`
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`

The row needs the `SyncActor` (to toggle per-comment seen) and the list of `ReviewComment`s belonging to its review. Both pass down from `PRDetailView`.

- [ ] **Step 1: Extend `TimelineEventRow` to accept the new props and render the threads**

Open `PRTracker/Views/Detail/TimelineEventRow.swift`. Add two new stored properties at the top of the struct:

```swift
struct TimelineEventRow: View {
    let event: TimelineEvent
    let reviewComments: [ReviewComment]   // pre-filtered to this event's review
    let syncActor: SyncActor
    var onTap: () -> Void
    var onMarkUpToHere: () -> Void
```

After the existing `cardContent` view, append the nested-threads region. Find the `cardContent` closing block (after `.background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))` — match the existing closing) and immediately after the call to render `cardContent` inside `body`, add a sibling region. Concretely, restructure the `body`:

```swift
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dot.padding(.leading, 4)

            VStack(alignment: .leading, spacing: 8) {
                if hasCard {
                    cardContent
                } else {
                    inlineContent
                }

                if event.type == .review {
                    nestedThreads
                }
            }
        }
        .opacity(event.isSeen ? 0.48 : 1.0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Mark up to here as seen", action: onMarkUpToHere)
            Button(event.isSeen ? "Mark unseen" : "Mark seen", action: onTap)
        }
    }
```

Then add `nestedThreads` as a private computed view at the bottom of the struct (above the `}` that closes the struct):

```swift
    @ViewBuilder
    private var nestedThreads: some View {
        let roots = reviewComments
            .filter { $0.inReplyToID == nil }
            .sorted { $0.createdAt < $1.createdAt }
        if !roots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(roots) { root in
                    let replies = reviewComments
                        .filter { $0.inReplyToID == root.id }
                        .sorted { $0.createdAt < $1.createdAt }
                    ReviewCommentThreadView(root: root, replies: replies, syncActor: syncActor)
                }
            }
        }
    }
```

- [ ] **Step 2: Thread `reviewComments` + `syncActor` through `TimelineColumn`**

Open `PRTracker/Views/Detail/TimelineColumn.swift`. Extend the struct:

```swift
struct TimelineColumn: View {
    let events: [TimelineEvent]
    let reviewComments: [ReviewComment]
    let syncActor: SyncActor
    var onTapEvent: (TimelineEvent) -> Void
    var onMarkUpToHere: (TimelineEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Tokens.hairline).frame(width: 1).padding(.leading, 13)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(events.sorted(by: { $0.at < $1.at })) { e in
                    TimelineEventRow(
                        event: e,
                        reviewComments: reviewCommentsFor(e),
                        syncActor: syncActor,
                        onTap: { onTapEvent(e) },
                        onMarkUpToHere: { onMarkUpToHere(e) })
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func reviewCommentsFor(_ event: TimelineEvent) -> [ReviewComment] {
        guard event.type == .review, let rid = event.reviewID else { return [] }
        return reviewComments.filter { $0.parentReviewIntegerID == rid }
    }
}
```

- [ ] **Step 3: Update the `TimelineColumn` call site in `PRDetailView`**

Open `PRTracker/Views/Detail/PRDetailView.swift`. Find the existing `TimelineColumn(events: ...)` call. Change it to:

```swift
TimelineColumn(
    events: pr.timeline,
    reviewComments: pr.reviewComments,
    syncActor: syncActor,
    onTapEvent: { e in Task { try? await syncActor.setSeen(eventID: e.id, isSeen: !e.isSeen) } },
    onMarkUpToHere: { e in Task { try? await syncActor.setSeenUpTo(prID: pr.id, throughEventID: e.id) } })
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Manually verify**

Run the app. Open a PR known to have code-level review comments (and ideally a reply). Confirm:
- Each review-event card shows nested threads beneath its body.
- Root comments show file:line breadcrumb + diff_hunk + author + body.
- Replies are indented under their root with a leading hairline rail; they show author + body only (no breadcrumb / diff_hunk).
- Markdown in bodies (bold, italic, links, inline code) renders styled.
- Right-clicking a comment toggles its seen-dim independently.
- Opening the PR continues to mark everything seen (existing behavior).

- [ ] **Step 7: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/TimelineEventRow.swift PRTracker/Views/Detail/TimelineColumn.swift PRTracker/Views/Detail/PRDetailView.swift
git commit -m "feat(detail): nest ReviewCommentThreadView under each parent review event"
```

---

## Task 11: Final smoke + PR

**Files:** none

- [ ] **Step 1: Run the full test suite one more time**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: All tests pass. New suites visible: `ReviewCommentDecodingTests` (3 cases), `SyncActorReviewCommentsTests` (9 cases).

- [ ] **Step 2: Manual smoke**

In the running app:
- Walk through several PRs to confirm the layout doesn't break for PRs with zero comments, PRs with only top-level comments, and PRs with a mix of reviews + line comments + replies.
- Toggle seen on a code comment via context menu; verify the 0.48-dim applies just to that card.
- Mark a PR as unread (right-click the row in the source list); reopen — confirm everything still loads correctly.
- Resize the detail pane width — confirm the nested thread cards reflow and stay legible.

- [ ] **Step 3: Open a PR against `main`**

```bash
git log --oneline main..HEAD | head -20
git push -u origin detail-improvments
gh pr create --base main --title "Detail-view code comments + markdown" --body "$(cat <<'EOF'
## Summary
- Fetch /pulls/{n}/comments alongside existing detail-load endpoints
- New ReviewComment @Model threaded under each parent review event
- MarkdownText helper renders inline markdown in review and comment bodies
- isSeen cascades from setSeenForPR / setSeenUpTo; per-comment seen toggle via context menu
- Spec: docs/superpowers/specs/2026-05-21-detail-improvements-design.md
- Plan: docs/superpowers/plans/2026-05-21-detail-improvements.md

## Test plan
- [x] Unit tests pass (`xcodebuild ... test`) — adds ReviewCommentDecodingTests + 9 SyncActorReviewCommentsTests
- [ ] Manual smoke: PR with code comments + replies renders nested threads correctly
- [ ] Manual smoke: markdown inline elements (bold / italic / inline code / links) render styled

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

(Skip the `gh pr create` if you'd rather merge locally first.)

---

## Self-Review

**Spec coverage:**
- §1 Goal — covered by overall plan
- §2 Approach — task order matches the vertical-slice ordering
- §3 Architecture — Task 1 (TimelineEvent.reviewID), Task 2 (DTO + endpoint + client), Task 3 (ReviewComment model + relationship + schema)
- §4 Sync wiring — Task 4 (upsertReviewComments), Task 5 (isSeen cascade), Task 6 (loadTimeline integration)
- §5 UI — Task 7 (MarkdownText + apply to existing bodies), Task 8 (ReviewCommentCard), Task 9 (ReviewCommentThreadView), Task 10 (wiring into TimelineEventRow / Column)
- §6 Markdown helper — Task 7
- §7 Behavior — Task 6 (loadTimeline), Task 5 (cascades), Task 10 (context-menu toggle)
- §8 Removed / unchanged — Plan respects: no Quick reply change, no right-rail change, no issueComments wiring
- §9 Testing — Task 2 (decoding), Tasks 4 + 5 (actor) — 12 new tests total
- §10 Risks — addressed during implementation; manual smoke covers them
- §11 Out of scope — respected (no diff viewer, no posting, no resolution, no syntax highlighting)

**Placeholder scan:** No "TBD" / "implement later" / "fill in details". Every code step shows actual code. The fixture-loader fallback in Task 2 Step 5 says "look at how `pulls_5107_comments` is loaded by reading the existing `GitHubClientTests.swift`'s `loadFixture` helper" — this is a redirect to the existing pattern, not a placeholder; the engineer will read the file. Acceptable.

**Type consistency:**
- `TimelineEvent.reviewID: Int?` (Task 1) — referenced consistently in Task 5 (cascade), Task 10 (filter), spec §3.
- `ReviewComment.parentReviewIntegerID: Int?` (Task 3) — matches `event.reviewID` everywhere it's filtered (Task 10).
- `ReviewComment.inReplyToID: String?` — string surrogate `"RC_<int>"` set by Task 4, matched by `$0.inReplyToID == root.id` in Task 10.
- `id` surrogate scheme `"RC_<github-id>"` (or `node_id` when present) — defined in Task 4, referenced in Tasks 5 and 10 consistently.
- `ReviewCommentCard(comment:showsAnchor:onToggleSeen:)` signature stable across Tasks 8, 9.
- `ReviewCommentThreadView(root:replies:syncActor:)` signature stable across Tasks 9, 10.
- `setSeen(reviewCommentID:isSeen:)` signature stable across Tasks 5, 8 (via Card), 9 (via Thread).

No outstanding issues.
