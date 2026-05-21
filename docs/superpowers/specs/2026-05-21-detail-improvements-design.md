# Detail-View Improvements — Design Spec

**Status:** Approved for plan-writing
**Date:** 2026-05-21
**Branch:** `detail-improvments`
**Spec depends on:** `docs/superpowers/specs/2026-05-19-mail-redesign-design.md`

## 1. Goal

Two additions to the PR detail pane:

1. **Show code-level review comments and their replies.** GitHub's per-line review comments (anchored to `path:line`) appear today only as the parent "reviewed" timeline event with no nested context. Bring them in, threaded under their parent review and grouped by root comment.
2. **Render comment bodies as markdown** using SwiftUI's built-in `AttributedString(markdown:)`. Inline-only fidelity (bold, italic, links, inline code, strikethrough). Block elements (headings, lists, fenced code blocks) degrade to literal markdown text.

Both work confined to the detail-pane timeline column. No sidebar / source-list changes. No quick-reply changes. Read-only — no posting / editing comments from the app.

The previous spec (`2026-05-19-mail-redesign-design.md`, §12) explicitly listed "inline-comment threads on diffs" as out-of-scope for v1. This work is a deliberate scope expansion past that boundary.

## 2. Migration approach

One branch, one PR, ordered as a vertical slice so every stage compiles and runs:

1. DTO + endpoint + sync wiring (no UI yet — verify sync via unit test on the actor)
2. `ReviewComment` `@Model` + relationship on `PullRequest` + `isSeen` cascade
3. UI: nested `ReviewCommentThreadView` inside each review event card
4. `MarkdownText` helper applied to review / comment bodies

## 3. Architecture

### New GitHub endpoint

`GET /repos/{owner}/{repo}/pulls/{number}/comments` → `[ReviewCommentDTO]`.

Added to `Endpoints.swift`, `GitHubClient.reviewComments(repo:, number:)`. Called in parallel with the existing detail-load fetches.

### New DTO

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

### New `@Model`

```swift
@Model final class ReviewComment {
    @Attribute(.unique) var id: String   // "RC_<github-id>" surrogate
    var parentReviewIntegerID: Int?      // matches TimelineEvent.reviewID
    var inReplyToID: String?             // self-reference for replies
    var author: User
    var body: String
    var path: String
    var line: Int?                       // falls back to original_line
    var diffHunk: String
    var createdAt: Date
    var isSeen: Bool                     // local-only, never overwritten by sync
    var pullRequest: PullRequest
}
```

### `TimelineEvent` change

Add one column so comments can find their parent review:

```swift
var reviewID: Int?                       // populated only for review events
```

`upsertTimeline` sets this from `dto.id` when `dto.event == "reviewed"`. The comment-DTO's `pull_request_review_id` is the same integer, so `comment.parentReviewIntegerID == event.reviewID` is the matching predicate. Additive SwiftData migration — existing rows default to `nil`.

The id surrogate `dto.node_id ?? "TI_\(id)"` cannot be reused here because the comment endpoint only returns the integer review id, not the parent review's node_id.

### `PullRequest` change

Add one cascade relationship:

```swift
@Relationship(deleteRule: .cascade, inverse: \ReviewComment.pullRequest)
var reviewComments: [ReviewComment] = []
```

SwiftData additive migration handles this automatically — existing PRs get an empty array on first launch.

## 4. Sync wiring

`PRDetailView.loadTimeline()` adds one parallel fetch:

```swift
async let rc = client.reviewComments(repo: ref, number: number)
let (tItems, reviewDTOs, _, detail, checks, comments) =
    try await (t, r, c, d, ck, rc)
try await syncActor.upsertTimeline(prID: prID, items: tItems)
try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs)
try await syncActor.upsertReviewComments(prID: prID, fromDTOs: comments)
try await syncActor.updatePRStatistics(prID: prID, dto: detail)
try await syncActor.upsertCIChecks(prID: prID, dto: checks)
```

### `SyncActor.upsertReviewComments(prID:, fromDTOs:)`

- For each DTO build `id = dto.node_id ?? "RC_\(dto.id)"`.
- Upsert by id: existing rows have `body`, `path`, `line`, `diffHunk` refreshed; `isSeen` preserved; `createdAt` left alone.
- Set `parentReviewIntegerID = dto.pull_request_review_id`. If the matching parent review event isn't yet in `pr.timeline`, the comment is still stored — the UI just won't find a host card for it until the next timeline refresh.
- Set `inReplyToID = dto.in_reply_to_id.map { "RC_\($0)" }`.
- Resolve `author` via the existing `upsertUser` helper.
- Set `line = dto.line ?? dto.original_line`.
- Delete any `ReviewComment` belonging to this PR whose id isn't in the new response (same purge pattern as `upsertTimeline`).
- `try ctx.save()`.

### isSeen cascade

Extend two existing methods:

- `setSeenForPR(prID:isSeen:)` — also iterate `pr.reviewComments`, set their `isSeen`.
- `setSeenUpTo(prID:throughEventID:)` — when the through-event is a review, also mark its child `ReviewComment`s seen. Comments whose parent review's event is at or before `target.at` flip.

Add one new method:

- `setSeen(reviewCommentID:, isSeen:)` — single comment toggle, used by the per-comment context menu.

## 5. UI

### Where it slots in

`TimelineEventRow` for `event.type == .review` is the only event row that gains a nested region. After the review's body Text (now rendered via `MarkdownText`), if any `ReviewComment` in the parent PR has `parentReviewIntegerID == event.reviewID`, append a `VStack(spacing: 8)` of `ReviewCommentThreadView`s. The row needs access to the parent `PullRequest`'s `reviewComments` collection — passed in alongside `event`, since `TimelineEvent.pullRequest` is already a relationship.

### `ReviewCommentThreadView`

Renders one root comment + its replies.

- Sort: roots by `createdAt` ascending; within a root, replies by `createdAt` ascending.
- Layout: VStack(alignment: .leading, spacing: 6). Root is a `ReviewCommentCard` at full width. Replies are `ReviewCommentCard`s indented `24pt` from the leading edge with a 1pt `Tokens.hairline` rail at `leading: 12` running their full height.
- Reply cards drop the breadcrumb + diff_hunk — those are inherited from the root. Replies just show author + body.

### `ReviewCommentCard`

Per-card layout (12pt vertical, 12pt horizontal, `Tokens.cardBg`, 0.5pt `Tokens.border`, cornerRadius 8):

1. **Breadcrumb row** — monospace `path:line` at 10.5pt medium `Tokens.textFaint`. Hidden on reply cards.
2. **diff_hunk block** (root cards only):
   - Monospace 11pt, `Tokens.textMuted`, `Tokens.hairline` background, `Tokens.border` outline, cornerRadius 6, padding 6pt vertical / 8pt horizontal.
   - Renders `comment.diffHunk` verbatim. No syntax highlighting. No per-line gutter.
3. **Author row** — 18pt `AvatarView` + name 12/semibold `Tokens.text` + `Spacer()` + relative time 10.5pt `Tokens.textFaint`.
4. **Body** — `MarkdownText(comment.body)`.

Card-level modifiers:
- `.opacity(comment.isSeen ? 0.48 : 1)` matches timeline-event dim behavior.
- `.contextMenu` with one item: "Mark seen" / "Mark unseen" toggling `comment.isSeen` via `syncActor.setSeen(reviewCommentID:isSeen:)`.

### Empty-state behavior

If a review event has no child `ReviewComment`s, the nested region simply isn't rendered. No "No comments" placeholder.

## 6. Markdown helper

New file: `PRTracker/DesignSystem/MarkdownText.swift`.

```swift
import SwiftUI

/// Renders a comment body using SwiftUI's built-in markdown support.
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

**Applied at three sites:**

1. `TimelineEventRow.cardContent` — replace the body `Text(body)` block with `MarkdownText(body)`.
2. `ReviewCommentCard` — body field.
3. Nowhere else. Status events, commit messages, branch names, breadcrumbs, and metadata copy stay as plain `Text`.

`.textSelection(.enabled)` lets reviewers copy snippets out of comments — small affordance, no cost.

## 7. Behavior summary

| Action | Effect |
|---|---|
| Open PR detail | `loadTimeline` fetches review comments alongside existing data; `upsertReviewComments` runs after `upsertTimeline` |
| Open PR detail | `setSeenForPR(isSeen: true)` cascades to `reviewComments` — all child comments marked seen |
| Right-click code comment → "Mark seen/unseen" | `setSeen(reviewCommentID:, isSeen:)` toggles the single comment |
| Right-click timeline review event → "Mark up to here" | Cascade still includes review comments whose parent review is at or before target.at |
| Sync deletes comment server-side | Next `upsertReviewComments` purges it from the local store |

## 8. Removed / unchanged code

**Unchanged:**
- Quick reply (still stubbed)
- Detail right rail
- All non-review timeline event rendering (commits, status, opened, merged, closed, labeled, assigned)
- The discarded `client.issueComments(...)` fetch — still discarded. `/timeline` already includes top-level conversation comments. Wiring this would be redundant and is out of scope.

**Removed:**
- Nothing.

## 9. Testing

**Unit tests (new):**

- `ReviewCommentParsingTests` — given a fixture JSON `pulls_5107_comments.json`, decode and verify field mapping (especially `original_line` fallback for `line`).
- `SyncActorReviewCommentsTests`:
  - `upsertReviewComments_insertsNew` — fresh DTOs land as new `ReviewComment`s.
  - `upsertReviewComments_updatesExistingByID` — re-running with mutated bodies updates in place; `isSeen` preserved.
  - `upsertReviewComments_purgesStale` — comment deleted on server is removed locally.
  - `upsertReviewComments_resolvesReviewParent` — `parentReviewIntegerID` correctly set from `pull_request_review_id`; matches a `TimelineEvent.reviewID` populated by `upsertTimeline`.
  - `setSeenForPR_cascadesToReviewComments` — calling with `isSeen: true` flips all child comments seen.
  - `setSeen_reviewCommentID_togglesOne` — pinpoint toggle works.

**Fixture:** `PRTrackerTests/GitHub/Fixtures/pulls_5107_comments.json` — small array of 3 comments: one root, one reply to that root, one independent root. Use the GitHub API's actual response shape.

**Manual smoke (can't be automated):**
- Open a PR with known code-level comments and replies. Confirm:
  - Each review event card shows nested threads beneath the review body.
  - Roots show file:line + diff_hunk; replies indent under their root with a leading rail.
  - Markdown in bodies (bold, italic, inline code, links) renders styled.
  - Fenced code blocks (` ``` `) render as literal text — known limitation, not a bug.
  - Right-clicking a code comment toggles its seen-dim.
  - Opening the PR marks everything seen as before.

## 10. Risks & open items

- **`AttributedString(markdown:)` parses link targets but doesn't open them on macOS click by default.** Verify during implementation whether `.textSelection(.enabled)` plus default `Link` parsing yields clickable links. If not, may need a small `.environment(\.openURL)` adjustment.
- **Large review threads (50+ comments) may slow render.** `LazyVStack` inside `ScrollView` would help, but the timeline column is already inside the existing `ScrollView` in `PRDetailView`. Profile if it becomes a problem; defer until needed.
- **Outdated comments** (those where the line they reference no longer exists in the diff) carry `line == nil` but a non-nil `original_line`. We use `original_line` as a fallback. We don't surface "outdated" status visually in v1 — out of scope.
- **Diff_hunk text wrapping.** Long lines in the hunk may need horizontal scrolling. Initial implementation uses `Text` with default wrapping; if hunks look bad, switch the hunk block to a horizontally-scrolling container in a follow-up.

## 11. Out of scope (intentionally not covered)

- Full file-diff view
- Posting / editing / deleting comments
- Resolving threads
- Reactions on comments
- Outdated-comment visual treatment
- Syntax highlighting in diff_hunk
- Issue-comments endpoint cleanup (`client.issueComments` stays unused — `/timeline` already covers it)
- Block-level markdown rendering (headings, lists, fenced code blocks beyond literal text)
