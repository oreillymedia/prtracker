# Todo-first Detail View — Design Spec

**Status:** Approved for plan-writing
**Date:** 2026-05-22
**Branch:** `notifications` (will be re-purposed, or moved to a fresh branch)
**Reference:** `handoff-todo/README.md` and `handoff-todo/pr-mail.jsx`

## 1. Goal

Replace read/unread as the primary state with **done/not-done at message granularity**. Every PR becomes a todo list: each non-mine comment is a checkable item, replies form sub-threads, a thread is resolved only when every non-mine message is checked, and a new non-mine reply re-opens a previously-resolved thread.

The source list, filter pills, detail body, and right-rail behavior all reorient around this single semantic. Read-state machinery (`isUnread`, unread dot, "Mark as unread") is retired.

## 2. Scope

**In scope:**
- Per-message `isDone` on `TimelineEvent` (top-level comments) and `ReviewComment` (line comments + replies)
- Derived `Thread` structs assembled per-render from existing SwiftData entities
- Source-list row rewrite: `TodoRing` + status chip, new filter set
- Detail body rewrite: `TodoSummaryBar` + `OPEN` / `RESOLVED` / `ACTIVITY` sections + `ThreadCard`s
- `MailFilter` enum expansion: new `Awaiting me` / `Open` / `Done` pills; drop `Review` / `Involved`
- Right-rail "Mark as unread" button removed
- `lastReadAt` column repurposed semantically as "last seen at"; updates on row selection, not detail open
- `Classifier`-style `bucketFor(pr:)` adapted to use ball-in-my-court precedence
- Minimal menubar patch to drop the `UnreadDot` reference

**Out of scope:**
- Reply functionality (composer dropped from the design entirely — `Resolve` is the only action on open threads)
- GitHub-side resolution of conversation threads (local-only)
- Multi-repo aggregation
- Settings / preferences screen changes
- Notification-center / menu-bar full redesign
- File-diff view, inline code blocks under thread messages
- Auth changes
- `ReviewComment.isSeen` and `TimelineEvent.isSeen` cleanup (both columns become orphaned but stay on the schema for migration safety)

## 3. Architecture

### High-level flow

```
SyncCoordinator (unchanged) → upserts TimelineEvent + ReviewComment
                                       ↓
                          Detail view renders → TodoHelpers.threads(for:viewerLogin:lastSeenAt:)
                                       ↓
                          ThreadsView splits into OPEN / RESOLVED, plus ACTIVITY for non-comment events
                                       ↓
                          User taps checkbox / Resolve / row → main-context mutation on isDone or lastSeenAt
```

### New / modified components

**Create:**
- `PRTracker/Models/TodoHelpers.swift` — pure functions returning `Thread` / `ThreadMessage` value types and todo counts.
- `PRTracker/DesignSystem/TodoRing.swift` — circular progress.
- `PRTracker/DesignSystem/TodoCheckbox.swift` — 18pt rounded checkbox.
- `PRTracker/Views/Detail/TodoSummaryBar.swift`
- `PRTracker/Views/Detail/ThreadsView.swift` — replaces `TimelineColumn` in the detail body.
- `PRTracker/Views/Detail/ThreadCard.swift` — replaces `TimelineEventRow` for comments; `TimelineEventRow` is reused only for the ACTIVITY section.
- `PRTracker/Views/Detail/ThreadMessageRow.swift` — one message row inside a card.
- `PRTracker/Views/Detail/ActivitySection.swift` — collapsible section containing non-comment events.
- `PRTrackerTests/Mail/TodoHelpersTests.swift` — pure-function tests for resolution rules.

**Modify:**
- `PRTracker/Models/TimelineEvent.swift` — add `var isDone: Bool = false`.
- `PRTracker/Models/ReviewComment.swift` — add `var isDone: Bool = false`.
- `PRTracker/Models/PullRequest.swift` — remove `isUnread` computed property; keep `lastReadAt` column; add `var lastSeenAt: Date? { lastReadAt }` doc accessor for readability.
- `PRTracker/Views/Mail/MailFilter.swift` — new cases; remove `.review` and `.involved`.
- `PRTracker/Views/Mail/MailRowView.swift` — full rewrite.
- `PRTracker/Views/Mail/MailListView.swift` — sort rule, row tap → `lastSeenAt = .now`.
- `PRTracker/Views/Mail/FilterPillBar.swift` — accent-tinted variant for `Awaiting me` when count > 0.
- `PRTracker/Views/Detail/PRDetailView.swift` — body switches to `ThreadsView`; right rail removes the unread button.
- `PRTracker/Views/Detail/DetailRightRail.swift` — drop the bottom button.
- `PRTracker/Views/Mail/MailDetailHeader.swift` — insert `TodoSummaryBar` below metadata row.
- `PRTracker/Sync/Classifier.swift` — add `ballInMyCourt(pr:viewerLogin:lastSeenAt:)`; relocate or remove `Section` enum (keep underlying lane mapping for rail color).
- `PRTracker/Views/MenuBar/MenuBarContentView.swift` — minimal patch: drop `UnreadDot`, replace `pr.isUnread` references with `prTodoCounts(pr).open > 0`.

**Delete:**
- `PRTracker/Views/Mail/UnreadDot.swift` — no consumers after the rewrite.

## 4. Data model

### `TimelineEvent`

```swift
var isDone: Bool = false   // additive — defaults false on existing rows
```

Only meaningful for `type == .comment`. Other event types ignore this field but it's declared on the model uniformly.

### `ReviewComment`

```swift
var isDone: Bool = false   // additive
```

Both `inReplyToID == nil` (roots) and replies use this same flag.

### `PullRequest`

```swift
// Column name unchanged: `lastReadAt`. Semantically now "last seen at" —
// the most recent moment the user selected this PR's source-list row.
// Updated by MailListView's selection handler. Not touched by detail-open
// any longer.
var lastReadAt: Date?

// Convenience for new code: read-only alias.
var lastSeenAt: Date? { lastReadAt }
```

Remove the old `isUnread` computed property entirely. Any code that referenced it must be updated to use `prTodoCounts(pr).open > 0` instead.

### `ViewerState`

No changes.

### Notes on retained-but-orphaned columns

- `TimelineEvent.isSeen` and `ReviewComment.isSeen` lose all consumers after this redesign. Keeping the columns avoids a SwiftData migration that removes columns (more fragile). They sit unused; a cleanup follow-up can delete them with `@Attribute(versioned:)` if and when migration tooling is firmed up.

## 5. Derived thread model

### `Thread` value type

```swift
enum ThreadKind {
    case reviewComment   // root ReviewComment + its in_reply_to chain
    case prComment       // single top-level TimelineEvent of type .comment
}

struct Thread: Identifiable {
    let id: String              // unique per render
    let kind: ThreadKind
    let location: String        // "Sources/Foo.swift:42" or "Discussion"
    let kindLabel: String?      // "Changes requested" when origin review state == .changesRequested
    let messages: [ThreadMessage]
}

struct ThreadMessage: Identifiable {
    let id: String              // TimelineEvent.id or ReviewComment.id
    let actor: User
    let createdAt: Date
    let body: String
    let isMine: Bool
    let isDone: Bool
    let isNew: Bool             // !isMine && !isDone && createdAt > lastSeenAt
    let underlying: ThreadMessageBacking  // tag to enable mutation
}

enum ThreadMessageBacking {
    case timelineEvent(eventID: String)
    case reviewComment(commentID: String)
}
```

### Helpers (`TodoHelpers.swift`)

```swift
func threads(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> [Thread] {
    var out: [Thread] = []

    // 1. PR-comment threads: top-level TimelineEvents of type .comment.
    for e in pr.timeline where e.type == .comment {
        let msg = makeMessage(timelineEvent: e, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
        out.append(Thread(id: "te_\(e.id)", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg]))
    }

    // 2. Review-comment threads: group by parentReviewIntegerID + in_reply_to chains.
    let comments = pr.reviewComments
    let rootsByReviewID = Dictionary(grouping: comments.filter { $0.inReplyToID == nil }, by: { $0.parentReviewIntegerID })
    for (reviewID, roots) in rootsByReviewID {
        for root in roots.sorted(by: { $0.createdAt < $1.createdAt }) {
            let replies = comments
                .filter { $0.inReplyToID == root.id }
                .sorted { $0.createdAt < $1.createdAt }
            let messages = ([root] + replies).map {
                makeMessage(reviewComment: $0, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
            }
            let kindLabel = originReviewKindLabel(reviewIntegerID: reviewID, in: pr)
            let location = "\(root.path)\(root.line.map { " L\($0)" } ?? "")"
            out.append(Thread(id: "rc_\(root.id)", kind: .reviewComment, location: location, kindLabel: kindLabel, messages: messages))
        }
    }

    return out.sorted { ($0.messages.last?.createdAt ?? .distantPast) > ($1.messages.last?.createdAt ?? .distantPast) }
}

func isResolved(_ thread: Thread) -> Bool {
    thread.messages.allSatisfy { $0.isMine || $0.isDone }
}

func hasNew(_ thread: Thread) -> Bool {
    thread.messages.contains { !$0.isMine && !$0.isDone && $0.isNew }
}

func openCount(_ thread: Thread) -> Int {
    thread.messages.filter { !$0.isMine && !$0.isDone }.count
}

struct TodoCounts: Equatable {
    let total: Int        // total threads
    let done: Int         // resolved threads
    let open: Int         // total - done
    let openMessages: Int // sum of open non-mine messages across all open threads
}

func todoCounts(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> TodoCounts {
    let ts = threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
    let total = ts.count
    let done = ts.filter(isResolved).count
    let openMessages = ts.reduce(0) { $0 + openCount($1) }
    return TodoCounts(total: total, done: done, open: total - done, openMessages: openMessages)
}

func ballInMyCourt(_ pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> Bool {
    if pr.state == .merged || pr.state == .closed { return false }
    let counts = todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
    if counts.openMessages > 0 { return true }
    // CHANGES_REQUESTED on a PR you authored counts as ball-in-court even
    // when no message-level todos remain (the author owes a fix).
    if pr.author.login == viewerLogin && pr.reviewState == .changesRequested { return true }
    return false
}
```

`originReviewKindLabel` looks up the matching `TimelineEvent` of type `.review` by `reviewIntegerID == event.reviewID` and returns `"Changes requested"` if its `reviewState == .changesRequested`, else `nil`.

## 6. Filter set + bucketing

### `MailFilter` after the rewrite

```swift
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case all, awaitingMe, open, mentions, mine, done, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        "All"
        case .awaitingMe: "Awaiting me"
        case .open:       "Open"
        case .mentions:   "Mentions"
        case .mine:       "Mine"
        case .done:       "Done"
        case .recent:     "Merged"
        }
    }
}
```

### Filter predicates

| Filter | Predicate (viewer = `viewerStates.first?.viewer?.login`) |
|---|---|
| `.all` | every PR |
| `.awaitingMe` | `ballInMyCourt(pr, viewer, pr.lastSeenAt)` |
| `.open` | `pr.state == .open && todoCounts(pr, viewer, pr.lastSeenAt).open > 0` |
| `.mentions` | `pr.mentionHint != nil` |
| `.mine` | `pr.author.login == viewer && pr.state == .open` |
| `.done` | `pr.state == .open && todoCounts(...).total > 0 && todoCounts(...).open == 0` |
| `.recent` | `pr.state == .merged` |

`MailFilter.dotColor` (for the pill dot) maps to the Lane palette as before; `.awaitingMe` is `.attention`, `.open` and `.done` are colorless (no dot — they're todo-state, not bucket-color).

### `bucketFor(pr:viewerLogin:)` — rail color

```text
pr.state == .merged                                 → .recent (purple)
ballInMyCourt(pr, viewer, lastSeenAt)               → .attention (orange)
pr.reviewers.contains where state == .pending && user == viewer → .review (blue)
pr.mentionHint != nil                               → .mentions (purple)
pr.author == viewer && pr.state == .open            → .mine (green)
otherwise                                            → .involved (gray)
```

The `Section` enum (`.attention/.review/.mentions/.mine/.involved/.recent`) is retained internally because the rail color and `bucketFor` still use it. It's no longer a direct mapping to `MailFilter`.

### Sort

Inside any filter, sort `ballInMyCourt(...)` PRs first (stable), then by `updatedAt` desc.

## 7. UI specification

### 7.1 Source-list row (`MailRowView` rewrite)

**Anatomy** (380pt wide, 10/12/11/14 padding T/R/B/L):

```
│3│ ⓘ TodoRing(24)   Title ............. 5h ago   │
│ │                  ◐ alex.chen · #5107  · Caught up  │
│ │                  Alex: extracted resolveByName(_:issuer:)…
```

- **Rail** (3pt absolute, leading 0): color from `bucketFor` lane. Opacity 0.5 when row is "dim" (resolved or merged & not selected).
- **TodoRing(24)** — see §7.5.
- **Top line**: title + relative time.
  - Weight 700 when ball-in-my-court, 500 when resolved/merged, 600 otherwise.
  - Color `accentText` when selected, else `text`. Single-line ellipsis.
- **Second line**: 15pt avatar + 11.5/500 muted author name + `· #num` faint tabular + spacer + status chip.
- **Status chip** (rightmost on second line):
  - Merged → "Merged" + merge glyph, purple, no background.
  - Resolved (open PR, `open == 0 && total > 0`) → "Caught up" + check, approved color, no background.
  - Ball-in-my-court (`openMessages > 0` for viewer) → accent pill: 5pt pulsing dot + "`N` for me" / "1 for me", `accentBg` background.
  - Else (open with unresolved threads but waiting on others) → "waiting on others", `textMuted`.
- **Preview line** (when present; hidden for resolved + merged): "`<FirstName>`: `<body>`" from the most recent open non-mine message across all threads, 11.5pt `textMuted`, 2-line clamp.
- **Row dim**: whole row drops to `opacity: 0.55` when `(resolved && !merged) || (merged && !selected)`. Rail itself to 0.5.

**Tap behavior**: set `pr.lastReadAt = .now` (the column that semantically means "last seen") AND `appState.selectedPRID = pr.id`. Save on the main `modelContext`.

### 7.2 Filter pill bar (`FilterPillBar` rewrite)

Seven pills in the new order: All / Awaiting me / Open / Mentions / Mine / Done / Merged.

Per pill:
- Inactive default: `cardBg`, `text`, 0.5pt `border`, 11.5/600.
- Active: `text` background, white foreground, no border. Looks like a dark inverted pill in light mode.
- **`Awaiting me` is special**: when count > 0 and inactive, use `accentBg` + `accent` foreground + weight 700 to draw the eye. When active, accent fill + white text.

Count badge inside each pill: 10/700 tabular-nums right of label. Hidden when 0.

### 7.3 Detail header — `TodoSummaryBar` (new)

Sits below the existing metadata row. Hidden when `todoCounts.total == 0`.

```
┌────────────────────────────────────────────┐
│ ⊙(32)  3 of 5 threads resolved             │
│        2 open messages to address          │
└────────────────────────────────────────────┘
```

- Padding 8/10 horizontal, border-radius 8, gap 10, vertical center.
- `approvedBg` background + 0.5pt approved-tinted border when resolved (`open == 0`).
- `accentBg` + 0.5pt accent-tinted border when awaiting (`open > 0`).
- Left: 32pt `TodoRing` (same component, larger size).
- Right text:
  - Resolved → "All caught up" (approved color) / "No outstanding feedback. Ready when CI is."
  - Awaiting → "`done` of `total` threads resolved" (accent color) / "`openMessages` open message(s) to address" (muted)

### 7.4 Detail body (`ThreadsView` replaces `TimelineColumn`)

Vertical stack:

1. **OPEN section** (default expanded, sorted: latest activity first):
   - `SectionHeading`: 6×6 accent dot + "OPEN" 11/700 uppercase letter-spacing 0.6 + count pill.
   - List of `ThreadCard`s for unresolved threads.
2. **RESOLVED section** (default collapsed when non-empty):
   - `SectionHeading`: 6×6 approved dot + "RESOLVED" + count pill.
   - Collapsible. Stacked `ThreadCard`s.
3. **ACTIVITY section** (default collapsed):
   - `SectionHeading`: 6×6 textFaint dot + "ACTIVITY" + count pill.
   - Reuses existing `TimelineEventRow` for non-comment event types (commits, opened, merged, closed, labeled, assigned, status). The rail + nested review-comment rendering inside `TimelineEventRow` is bypassed by passing `reviewComments: []`.

**Section gap**: 18pt margin between sections.

**Empty state**: when PR has zero threads AND zero non-comment events, show a centered "No conversation on this PR yet." card. If non-comment events exist but no threads do, render only the ACTIVITY section (no empty-state card).

### 7.5 `TodoRing`

```swift
struct TodoRing: View {
    enum State { case allResolved, awaitingMe, waiting, empty }

    let done: Int
    let total: Int
    let size: CGFloat
    let state: State

    var body: some View {
        ZStack {
            // Track
            Circle().stroke(Tokens.hairline, lineWidth: size * 0.1)
            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(arcColor, style: .init(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
            // Center label
            centerLabel
        }
        .frame(width: size, height: size)
    }

    private var progress: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    private var arcColor: Color {
        switch state {
        case .allResolved: return Tokens.approved
        case .awaitingMe:  return Tokens.accent
        case .waiting:     return Tokens.textFaint
        case .empty:       return Tokens.hairline
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if total == 0 {
            Circle().fill(Tokens.textFaint).frame(width: 2, height: 2)
        } else if done == total {
            Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(Tokens.approved)
        } else {
            Text("\(done)/\(total)")
                .font(.system(size: size * 0.42, weight: .bold).monospacedDigit())
                .foregroundStyle(arcColor)
        }
    }
}
```

Used at 24pt in source-list rows; 32pt in the summary bar.

### 7.6 `ThreadCard`

**Chrome:**
- Border-radius 10, `cardBg` background, 0.5pt border (color = `Tokens.accent.opacity(0.4)` when `hasNew(thread)`, else `Tokens.border`).
- Drop shadow (`cardShadow`) when open; none when resolved.
- Opacity 0.78 when resolved.
- Collapsed by default when resolved, expanded by default when open. State persists in view-state (`@State private var collapsed`).

**Header** (10/12 padding, gap 10, cursor pointer):
- Status tile (22×22 radius 6 flex-shrink 0):
  - Resolved → approved background + white 13pt check.
  - Has new → accent background + white `done/totalNonMine` 10/700 tabular.
  - Otherwise → hairline background + `textMuted` `done/totalNonMine`.
- Middle text:
  - Top line: optional kind label (10/700 uppercase letter-spacing 0.5) + middle dot + location (12.5/600 — monospaced when file-anchored, sans when `where == "Discussion"`).
  - Sub-line (margin-top 2): "Resolved" (muted) when resolved, else "`openCount` open · `n` messages".
- "Resolve" button (only when not resolved and totalNonMine > 0; full-width-of-header equivalent — small, 11/600, hairline border): stops propagation. Resolves all non-mine messages in the thread.
- Chevron 11pt faint at right, `.rotationEffect(-90°)` when collapsed.

**Message rows** (inside, 10/12 padding):
- Background `newHighlight` when message is new and not done; transparent otherwise.
- Left border 3pt accent when new and not done; transparent otherwise.
- Opacity 0.5 when done and not mine.
- Leading rail (18pt):
  - Non-mine → `TodoCheckbox(isOn: msg.isDone)` 18×18, radius 5.04, 1.5pt `borderStrong` border when unchecked, approved fill + white 12pt check when checked. Tap toggles `isDone` on the underlying SwiftData record. Stops propagation.
  - Mine → "↳" glyph (9/700 textFaint uppercase letter-spacing 0.4). No interaction.
- 22pt `AvatarView`.
- Body (flex 1):
  - Header line: author 12/600 (strikethrough when done & not mine) + "YOU" tag (mine: 9.5/700 textMuted hairline bg uppercase) + "NEW" tag (`isNew == true`: 9.5/700 accent accentBg uppercase) + spacer + time 10.5pt faint.
  - Body via existing `MarkdownText`.

**Footer:** Single "Resolve" full-width secondary button (`cardBg` + 0.5pt border + radius 6 + 6pt vertical padding). Visible only when the thread has at least one non-mine, non-done message. Tap → mark all non-mine messages `isDone = true`. No reply composer.

### 7.7 `TodoCheckbox`

18×18 SwiftUI view. Two states. Tap inverts `isDone` and saves on the main `modelContext`.

```swift
struct TodoCheckbox: View {
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.04)
                    .fill(isOn ? Tokens.approved : .clear)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5.04)
                        .stroke(isOn ? .clear : Tokens.borderStrong, lineWidth: 1.5))
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

### 7.8 Right rail changes

- Drop the bottom "Mark as unread" button entirely. The `onToggleReadState` parameter on `DetailRightRail` goes with it.
- Keep CI Checks rollup, Reviewers (excluding author), Labels, Changes, etc.

## 8. Behavior summary

| Action | Effect |
|---|---|
| Row tap in source list | `pr.lastReadAt = .now`; `appState.selectedPRID = pr.id`; ctx.save() |
| Open detail (auto, via `.task(id: pr.id)`) | Continue to `loadTimeline()` for remote data; no longer touches lastReadAt or isSeen |
| Filter pill tap | `appState.activeFilter = pill`; reconcile selection per `SelectionReconcile.next` |
| Thread checkbox tap | underlying record's `isDone = true/false`; ctx.save(); ring + summary bar re-render |
| Thread "Resolve" footer tap | For every non-mine message in the thread, set `isDone = true`; ctx.save(); thread migrates from OPEN to RESOLVED |
| Sync brings in a new non-mine message | New event/comment is inserted with `isDone = false`; its parent thread reverts to OPEN if it was resolved |
| Thread header tap | Toggle `collapsed` (view-state only; not persisted) |
| Open / Resolved / Activity section header tap | Toggle section collapse (view-state only; not persisted) |

## 9. Notification dispatcher (paused branch) compatibility

The paused `notifications` design fires on new comments (TimelineEvent.type == .comment) + new ReviewComments + CI failures + state changes. None of these depend on read-state. With the new todo semantics they remain valid; the dispatcher does not need awareness of `isDone`.

When that branch resumes, no additional spec changes are required for it to coexist with this redesign.

## 10. Testing

**Unit tests (new):** `TodoHelpersTests.swift`:
- `isResolved_emptyThread` returns true (vacuously).
- `isResolved_onlyMineMessages` returns true.
- `isResolved_oneOpenNonMine` returns false.
- `isResolved_allNonMineDone` returns true.
- `openCount_onlyCountsNonMineNotDone` validates count math.
- `hasNew_requiresAllThree` (not-mine, not-done, isNew).
- `todoCounts_emptyPR` returns zero counts.
- `todoCounts_mixed` (3 threads: 1 done, 2 open with 2+1 open messages) returns total 3, done 1, open 2, openMessages 3.
- `ballInMyCourt_changesRequested_onMyPR` returns true even when no open messages.
- `ballInMyCourt_othersPR_noOpenMessages` returns false.
- `ballInMyCourt_othersPR_oneOpenMessage` returns true.
- `threadKindLabel_changesRequested` returns "Changes requested" when origin review state matches.

These tests use synthetic `PullRequest` fixtures via `TestContainer.make()` similar to existing `PullRequestReadStateTests` patterns.

**Existing tests to update:**
- `PullRequestReadStateTests` — remove if `isUnread` is dropped; or repurpose to assert `lastReadAt` is still readable as `lastSeenAt`. Recommend removal.
- `MailFilterTests` — replace expectations for the new pill set (Awaiting me / Open / Done) and the dropped `.review` / `.involved` cases.
- `SyncActorReviewCommentsTests` — `setSeen(reviewCommentID:)` test stays (the method is unused but not removed in this PR — out-of-scope cleanup).

**Manual smoke (can't be automated):**
- Load a PR with multiple review-comment threads + a PR conversation comment. Open detail: confirm OPEN section shows N cards, RESOLVED is empty.
- Tap a checkbox on a single message. Confirm: that message's row dims with strikethrough, the thread's status tile updates `done/total`, the summary bar's ring updates, and the source-list row's TodoRing updates.
- Resolve all messages in a thread. Confirm thread migrates to RESOLVED section.
- Receive a new reply (manual sync). Confirm thread returns to OPEN.
- Filter by `Awaiting me`: only PRs with open messages or CHANGES_REQUESTED on viewer's own PRs appear.
- Filter by `Done`: only open PRs with all threads resolved appear.
- Filter by `Merged`: only merged PRs appear; no source-list TodoRing on them (or empty-state ring).
- Open ACTIVITY section: see commits, opened event, etc.
- Source-list row tap updates `lastSeenAt`; subsequent message "NEW" tags reflect that timestamp.

## 11. Risks & open items

- **`Section` enum retained as internal type.** Even after `MailFilter` drops `.review` and `.involved`, the underlying lane mapping uses these cases for rail color. Keeping the enum but limiting its public surface is the practical choice.
- **Threads derived per-render.** At typical PR scale (100s of PRs × 10 threads × 5 messages = ~5000 messages) this is fine. If detail-pane rendering becomes janky, memoize via `@State` keyed on `(pr.id, pr.timeline.count, pr.reviewComments.count, isDoneVersion)`.
- **`isDone` columns survive on event types that don't use them.** `TimelineEvent.isDone` is only meaningful for `type == .comment`. The other types ignore it. Acceptable.
- **No GitHub round-trip for resolution.** Resolving a thread locally does not call GitHub's "Resolve conversation" API. If a teammate resolves the thread on github.com, our local store stays at whatever isDone state the user chose. The next sync pulls fresh comment content but does not affect isDone (preserved across upserts). Long-term, a follow-up could call `mutation resolveReviewThread` on the GraphQL API.
- **Activity section reuse of `TimelineEventRow`.** That view currently handles its own per-event tap → `setSeen` and contextMenu. With isSeen orphaned, those tap handlers no-op visually. Either disable the row's tap inside Activity (recommended) or accept the no-op. Spec choice: disable.
- **Empty-state for the OPEN section when threads exist but all are resolved.** Show OPEN section heading with count 0? Or hide it entirely? Spec choice: **hide** the heading when count is 0 in either section. Only show ACTIVITY heading if there are non-comment events.

## 12. Out of scope (intentionally not covered)

- Reply composer (textarea + Reply / Reply & resolve)
- GitHub resolveReviewThread mutation
- Cleaning up orphaned `isSeen` columns (separate migration follow-up)
- Per-message context menu in Activity section
- Notification dispatcher changes (independent branch)
- Multi-repo / Settings / Onboarding tweaks
- Tweaks panel (the prototype's runtime tweaks for palette / groupResolved / showWhere) — ship defaults only
