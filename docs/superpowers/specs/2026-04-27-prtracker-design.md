# PR Tracker — Design (v1)

**Date:** 2026-04-27
**Status:** Approved for planning
**Target platform:** macOS 26+, SwiftUI, SwiftData
**Audience:** Single developer (the author) tracking pull requests for one GitHub repository at a time

## 1. Goal

A native macOS app that keeps a developer up to date on pull requests for a single repository. The main window is a feed of PRs grouped into priority sections (needs attention / needs review / mine / mentions / involved / recently merged), each PR drillable into a detail view with a unified timeline of commits, reviews, and comments. A menu-bar status item gives at-a-glance counts when the window is hidden. Read/unread state is tracked locally per timeline event, fully independent of GitHub's notifications.

The complete visual design (colors, typography, density, gauge style, lane palette, layout) is fixed and lives in `handoff/`. This document covers architecture, data, networking, behavior, and testing — not visual design.

## 2. Scope

### In v1

- Feed window with priority sections, PR cards, status gauges
- PR detail view with timeline, right rail (status, CI, reviewers, labels, changes), and a placeholder quick-reply block
- Local seen/unseen state at the per-timeline-event grain
- Periodic auto-refresh (2 min foreground, 10 min background) plus manual refresh
- Menu-bar status item with dropdown and red attention-count badge
- PAT-based GitHub authentication (token stored in macOS Keychain)
- Settings: refresh interval, repository, account, launch-at-login

### Phase 2 (explicitly out of v1)

- System notifications when a PR enters "needs my attention"
- Manual theme toggle (v1 follows system appearance)
- Density picker (the wiring exists; the UI does not)
- Multi-repo switcher in the sidebar (the schema supports it; the UI is read-only)
- Submitting reviews/comments from the quick-reply block (the textarea renders; buttons are disabled)
- GitHub OAuth device flow (v1 uses PAT only)
- GitHub Enterprise hosts

## 3. Architecture

Four layers, top-down.

### 3.1 App shell

`PRTrackerApp` declares three scenes sharing one `ModelContainer`:

- `WindowGroup("PR Tracker")` — main window, default 1280×820, `.windowResizability(.contentMinSize)`, min 960×600.
- `MenuBarExtra("PR Tracker", systemImage: "arrow.triangle.pull").menuBarExtraStyle(.window)` — custom dropdown content.
- `Settings { SettingsView() }` — standard ⌘, panel.

`RootView` switches between `OnboardingView` (no PAT or no validated viewer) and `MainView` (PAT present + viewer resolved).

### 3.2 UI (SwiftUI)

- `MainView` — `NavigationSplitView` with `Sidebar` (220pt, `.ultraThinMaterial`) and a detail area that contains either `FeedView` or `PRDetailView` based on `AppState.selectedPR`.
- `FeedView` — toolbar + scrollable column of collapsible `FeedSection` views containing `PRCardView` rows. Built with `ScrollView { LazyVStack }`, not `List`, because of custom styling/translucency.
- `PRDetailView` — header bar + two-column body (`TimelineColumn` left, `DetailRightRail` right at 260pt).
- `MenuBarContentView` — fixed-width 320pt dropdown (header, section rows, highlight row, action rows).
- `OnboardingView`, `SettingsView`.

### 3.3 Domain layer (no SwiftUI imports)

- `GitHubClient` — actor wrapping `URLSession`. Public surface is async/throws methods that return DTOs (plain `Decodable` structs mirroring REST shape).
- `SyncCoordinator` — owns the refresh ticker, debounces, and orchestrates calls to `GitHubClient` → `SyncActor`. Publishes `isSyncing`, `lastSyncAt`, `lastSyncError` on `AppState`.
- `SyncActor` — a `@ModelActor` that owns the writing `ModelContext`. All upserts run here.
- `Classifier` — pure functions. `Classifier.section(for: PullRequest, viewer: User, notifications: [NotificationDTO]) -> Section.Kind`. The notifications list is transient (never persisted) — fetched fresh on every refresh and passed into the classifier so it can compute the `mentions` section without scanning comment bodies.
- `Keychain` — minimal Security-framework wrapper for the PAT.

### 3.4 Persistence (SwiftData)

The cached PR list IS the persisted list. Every fetch is an upsert. The app opens to last-known data instantly and refresh becomes a diff, not a wipe. See §4.

### 3.5 State

A single `@Observable AppState` holds non-persisted runtime state: `activeSection`, `selectedPR`, `isSyncing`, `lastSyncAt`, `lastSyncError`, `rateLimit`. Persisted prefs live in the SwiftData `ViewerState` row. The PAT lives in Keychain.

Views read PR data via `@Query` directly against SwiftData; we do not duplicate data into `AppState`.

### 3.6 Concurrency

- `GitHubClient` is an actor.
- `SyncActor` is a `@ModelActor` with its own `ModelContext` — all writes happen there.
- Per-PR check-run fetches use `withTaskGroup` with at most 5 in flight.
- View reads use the main `ModelContext` via `@Query`.

### 3.7 Project layout

```
PRTracker/
  App/             PRTrackerApp.swift, AppState.swift, RootView.swift
  Models/          Repo.swift, PullRequest.swift, TimelineEvent.swift,
                   User.swift, Reviewer.swift, Label.swift, CIRun.swift,
                   ViewerState.swift, HTTPCache.swift
  GitHub/          GitHubClient.swift, Endpoints.swift, DTOs.swift, GitHubError.swift
  Sync/            SyncCoordinator.swift, SyncActor.swift, Classifier.swift
  Keychain/        Keychain.swift
  Views/Feed/      FeedView.swift, Sidebar.swift, FeedToolbar.swift,
                   FeedSection.swift, PRCardView.swift, StatusGauge.swift
  Views/Detail/    PRDetailView.swift, TimelineColumn.swift,
                   TimelineEventRow.swift, DetailRightRail.swift, QuickReply.swift
  Views/MenuBar/   MenuBarContentView.swift, MenuBarIconRenderer.swift
  Views/Onboarding/ OnboardingView.swift
  Views/Settings/  SettingsView.swift
  DesignSystem/    Tokens.swift, LaneColors.swift, Typography.swift, Density.swift
PRTrackerTests/
  Classifier/      ClassifierTests.swift
  GitHub/          GitHubClientTests.swift, Fixtures/*.json
  Sync/            SyncActorTests.swift
```

The existing `Item.swift` is removed; the existing `ContentView.swift` is replaced.

## 4. Data model

All SwiftData `@Model` types. Fields marked **local-only** are never overwritten by sync; everything else is server-owned and updated on every fetch.

### `Repo`

- `id: String` (`"owner/name"`, primary key)
- `owner: String`, `name: String`
- `lastFetchedAt: Date?`
- `isActive: Bool` — exactly one row has `true` in v1
- `@Relationship(deleteRule: .cascade) pullRequests: [PullRequest]`

### `PullRequest`

- `id: String` (GitHub node ID, primary key)
- `number: Int`, `title: String`
- `state: PRState` (`open`, `closed`, `merged`, `draft`)
- `branchHead: String`, `branchBase: String`
- `additions: Int`, `deletions: Int`, `changedFiles: Int`
- `openedAt: Date`, `updatedAt: Date`, `mergedAt: Date?`
- `reviewState: ReviewState?`, `mergeable: Mergeable`
- `ciPass: Int`, `ciFail: Int`, `ciRunning: Int`, `ciPending: Int`, `ciTotal: Int`
- `attentionHint: String?`, `mentionHint: String?`, `involvedHint: String?` — synthesized by `Classifier` during sync, stored for fast feed rendering
- `headSha: String` — for check-runs lookup
- `author: User`
- `repo: Repo` (inverse)
- `@Relationship(deleteRule: .cascade) timeline: [TimelineEvent]`
- `@Relationship(deleteRule: .cascade) reviewers: [Reviewer]`
- `@Relationship(deleteRule: .cascade) labels: [Label]`
- `@Relationship(deleteRule: .cascade) ciChecks: [CIRun]`

### `TimelineEvent`

- `id: String` (GitHub event ID, primary key)
- `type: EventType` (`commit`, `opened`, `review`, `comment`, `status`, `merged`, `closed`, `assigned`, `labeled`)
- `at: Date`
- `actor: User?` (system events have no actor)
- `body: String?`
- `sha: String?`
- `reviewState: ReviewState?`
- **`isSeen: Bool`** (default `false`, **local-only**)
- `pullRequest: PullRequest`

### `User` (referenced, not owned)

- `login: String` (primary key)
- `name: String?`
- `avatarURL: URL?`

Populated passively by `SyncActor`: every REST response embeds the user object on comments, reviews, commits, etc., so the cache fills in without separate `/users/{login}` calls.

### `Reviewer`

- `user: User`
- `state: ReviewState` (`PENDING`, `APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`)
- `pr: PullRequest`

### `Label`

- `name: String`
- `pr: PullRequest`

### `CIRun`

- `name: String`
- `state: CIState` (`pass`, `fail`, `running`, `pending`)
- `durationSeconds: Int?`
- `pr: PullRequest`

### `ViewerState` (singleton-ish row)

- `viewer: User?` (the authenticated user)
- `activeRepoID: String?`
- `refreshIntervalMinutes: Int = 2`
- `launchAtLoginEnabled: Bool = false`

### `HTTPCache`

- `url: String` (primary key)
- `etag: String?`
- `lastModified: String?`
- `fetchedAt: Date`

### Derived (never stored)

- A PR is **unread** (card shows the dot, bold title, full opacity) iff `pr.timeline.contains { !$0.isSeen }`.
- The card hint shown on unread PRs is the most recent unseen event of type `comment` or `review`.
- Section classification is computed at query time by `Classifier` (the `attentionHint` field is just a cached display string, not the source of truth for which section the PR belongs to).

### Seen-state mutations

The only writes outside sync. All five paths converge on `SyncActor.setSeen(...)`:

1. **Click a timeline event** → toggles `isSeen`. Click is reversible: clicking a seen event marks it unseen.
2. **Right-click a timeline event → "Mark everything up to here as seen"** → sets `isSeen = true` for all events on that PR with `at <= target.at`.
3. **Right rail button** "Mark all as seen" / "Mark all as unseen" (label flips based on state) → bulk set on the open PR.
4. **Right-click a PR card** → context menu "Mark seen" / "Mark unseen" → same as #3, from the feed.
5. **Sync-side default**: brand new events arriving via sync default to `isSeen = false`. So a freshly arrived comment makes the card bold again.

Opening a PR detail view does **not** auto-mark anything as seen.

### Upsert algorithm (`SyncActor`)

For each PR in the response:
1. Lookup by `id`. If present: update server-owned fields. If absent: insert.
2. Merge timeline events by `id`: insert new (with `isSeen = false`), update changed fields on existing (preserving `isSeen`), leave events the response doesn't mention alone unless this is a full timeline fetch (detail view) — in which case events absent from the response are deleted.
3. For each user object encountered (author, actor, reviewer, commenter), upsert into `User` by `login`.
4. PRs present in the store with `state == open` that are absent from the response: mark `state = closed` (we don't know the actual closed state, but they are no longer open).

When `headSha` changes on an existing PR, `pr.ciChecks` is cleared before the new check-runs are inserted (the old ones are stale).

Local-only fields (`isSeen`) are never written by sync.

## 5. Networking & auth

### 5.1 Authentication

- v1 uses a GitHub Personal Access Token (PAT). Classic or fine-grained both work.
- Token stored in macOS Keychain. Service `"com.prtracker.github"`, account `"pat"`.
- Onboarding: paste PAT → `GET /user` to validate → on success, save token + populate `ViewerState.viewer`.
- Token rotation: user pastes a new value; the next request picks it up (no caching of the token in the client).
- 401 from any endpoint: wipe Keychain, route to `OnboardingView` with "Token rejected" banner.

### 5.2 GitHubClient surface

```
actor GitHubClient {
    func validate() async throws -> User
    func listOpenPRs(repo: RepoRef) async throws -> [PullRequestDTO]
    func listRecentlyMerged(repo: RepoRef, limit: Int) async throws -> [PullRequestDTO]
    func checkRuns(repo: RepoRef, ref: String) async throws -> CIChecksDTO
    func participatingNotifications() async throws -> [NotificationDTO]
    func timeline(repo: RepoRef, number: Int) async throws -> [TimelineItemDTO]
    func reviews(repo: RepoRef, number: Int) async throws -> [ReviewDTO]
    func issueComments(repo: RepoRef, number: Int) async throws -> [CommentDTO]
}
```

### 5.3 REST endpoints used

Feed refresh:
- `GET /repos/{owner}/{repo}/pulls?state=open&sort=updated&direction=desc&per_page=50`
- `GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=20` (filtered to `merged_at` within 7 days for the "recent" section)
- For each open PR: `GET /repos/{owner}/{repo}/commits/{headSha}/check-runs`
- `GET /notifications?participating=true` (source of truth for the `mentions` section)
- `GET /user` once per session, cached

Detail view (lazy, on open and on every refresh while open):
- `GET /repos/{owner}/{repo}/issues/{number}/timeline?per_page=100`
- `GET /repos/{owner}/{repo}/pulls/{number}/reviews`
- `GET /repos/{owner}/{repo}/issues/{number}/comments`

### 5.4 Headers

Every request:
- `Authorization: Bearer <PAT>`
- `Accept: application/vnd.github+json`
- `X-GitHub-Api-Version: 2022-11-28`
- `User-Agent: PRTracker/1.0`

### 5.5 Conditional requests / caching

`HTTPCache` rows store `etag` and `last-modified` per URL. Every request adds `If-None-Match` / `If-Modified-Since`. On `304`, the client returns a `.notModified` sentinel and `SyncActor` skips that endpoint's upsert.

### 5.6 Rate-limit handling

Every response: parse `X-RateLimit-Remaining` and `X-RateLimit-Reset`, store on `AppState.rateLimit`. If `remaining < 50`, the next refresh tick is skipped until `reset`. On `403` with a rate-limit body, the toolbar shows a yellow chip with the reset time.

### 5.7 Pagination

v1 caps at one page each: 50 open + 20 closed. No infinite scroll. If a repo exceeds these, the bottom of the closed list shows "showing recent 20 merged" and that's it.

### 5.8 Errors

```
enum GitHubError: Error {
    case unauthorized                 // 401
    case repoNotFound                 // 404 on /repos/{owner}/{repo}
    case rateLimited(resetAt: Date)   // 403 + rate-limit body
    case network(underlying: Error)   // URLError, DNS, etc.
    case decoding(underlying: Error)  // schema drift
}
```

## 6. UI behavior

### 6.1 Sidebar

- Repo header (read-only in v1; clickable in Phase 2)
- Section list: All, Needs my attention, Needs my review, Mentions, My open PRs, Others' PRs (involved), Recently merged
- Each row: 4×14 colored rail, label, count pill (hidden when count == 0)
- Footer: viewer avatar + name + `@login` + gear button (opens Settings)
- Selection binds to `AppState.activeSection`

### 6.2 Feed

- Toolbar: title, repo subtitle, sync status chip ("Updated 2m ago" / spinner / error), refresh button
- When `activeSection == .all`: rendered as collapsible sections; chevron rotates between 0° and -90° (150ms)
- When a single section is selected: cards only, no header
- Cards: as in handoff (lane rail, unread dot, number, title, time, author, branch, gauge, optional hint bubble)
- Read styling: `.opacity(0.5)`, title weight `.medium` instead of `.semibold`
- Hover: stronger border + fade-in eye-toggle button (150ms)
- Click → opens detail
- Right-click → "Mark seen" / "Mark unseen", "Open on GitHub"

### 6.3 Status gauge (bars)

Three 34×4 bars (Review, CI, Merge) with a 6px gap. `running` state shimmers via `Canvas` + `TimelineView(.animation)`, 1.4s linear infinite. Style is a parameter; alternate styles (`pills`, `dots`) stubbed but not implemented in v1.

### 6.4 Detail view

- Header: back button ("◀ Feed"), `repo / #NNNN`, "Open" pill linking to GitHub
- Title (18 / 700 / -0.2)
- Meta line: author, "wants to merge into" base, "from" head, "opened Nd ago"
- **Timeline column**:
  - 1pt vertical rail at left=13, 20pt circular dots floated at left=4 with 2pt content-bg border
  - Comment / review-with-body → card style (cardBg, hairline border, 8pt radius, 10/12 padding)
  - Commit / status / opened → inline row
  - `isSeen == false` → full opacity + 22%-accent glow ring on the dot + 4×28 vertical accent bar at left=-4
  - `isSeen == true` → 0.48 opacity, no glow, no accent bar
  - Tap → toggles `isSeen`
  - Right-click → "Mark up to here as seen", "Mark this as seen/unseen"
- **Quick-reply block**: avatar, "Reply as <name>", `TextEditor`, three buttons (Approve / Request changes / Comment). In v1 the textarea renders; buttons are disabled with tooltip "Coming soon".

### 6.5 Right rail (260pt)

- Status (Review / CI / Mergeable rows with pills)
- CI checks list (per-check rows with icon + name + duration)
- Reviewers (avatar + name + state pill)
- Labels (chip cluster)
- Changes line (`+142 −38 · 7 files`)
- Single button at bottom: "Mark all as seen" / "Mark all as unseen" (label flips based on whether any event is unseen)

### 6.6 Menu-bar dropdown

Fixed-width 320pt:
- Header: repo name (bold) + "Updated Xs ago" (muted)
- Four section rows (attention/review/mine/mentions) with colored dots + counts; clicking activates the main window with that section selected
- Highlight row: top item from `attention` if any (PR title + most-recent comment snippet, italic muted); clicking opens detail
- Action rows: "Open PR Tracker", "Refresh now ⌘R", "Preferences… ⌘,"
- "Quit ⌘Q"

The status item icon is built dynamically from `arrow.triangle.pull` + a red 13×13 circular badge when `attention > 0`, composed via `NSImage` and exposed as the `MenuBarExtra` image.

### 6.7 Onboarding

Single card flow:
1. Paste PAT → "Validate" button → calls `GET /user`
2. On success, prompt for `owner/repo` → `GET /repos/{owner}/{repo}` to verify access
3. Save → enter `MainView`, kick first `SyncCoordinator.refresh()`

### 6.8 Settings

Three tabs:
- **General**: refresh interval slider (1–10 min, default 2), launch-at-login toggle (uses `SMAppService.mainApp`)
- **Account**: viewer avatar + name + `@login` + "Sign out" (clears Keychain, returns to onboarding)
- **Repository**: `owner/repo` text field + "Switch" button (re-validates and replaces active repo)

## 7. Refresh, lifecycle, menu bar

### 7.1 Cadence

- `refreshIntervalForeground` = 2 min (configurable in Settings)
- `refreshIntervalBackground` = 10 min (fixed)
- App becomes active (`scenePhase == .active`) → immediate refresh if `lastSyncAt` is older than 30s (debounced)
- Window hidden / occluded (via `NSApplication.shared.occlusionState` and `NSWindow.didChangeOcclusionStateNotification`) → switch to background interval; menu-bar still ticks
- Sleep / wake — on `NSWorkspace.didWakeNotification` fire a refresh and resume; on `willSleepNotification` suspend
- A detail view that is currently open re-fetches its timeline on every global refresh tick (so the user watching a PR sees it update live)

### 7.2 Refresh flow (`SyncCoordinator.refresh()`)

1. If `isSyncing`, return (coalesce concurrent calls)
2. Set `isSyncing = true`, clear `lastSyncError`
3. Concurrently: `listOpenPRs`, `listRecentlyMerged`, `participatingNotifications`. Await all
4. `SyncActor.upsertFeed(...)` — single transaction
5. For each PR's `headSha`, kick check-run fetch via `withTaskGroup` (max 5 in flight); each result → `SyncActor.upsertCIChecks(prID:, dto:)`
6. If a detail view is open, refresh its timeline + reviews + comments
7. On success: `lastSyncAt = .now`, `isSyncing = false`. On failure: store `lastSyncError`, leave `lastSyncAt` alone (UI keeps showing the previous successful timestamp + an error indicator)

### 7.3 Menu-bar status item

Always present, regardless of window visibility. The icon recomputes when the count of unread `attention` PRs changes. Clicking the icon opens the dropdown. "Open PR Tracker" uses `@Environment(\.openWindow)` with id `"main"`.

## 8. Errors & edge cases

### 8.1 Three-tier error surfacing

1. **Toolbar chip** (passive): rate-limited (yellow), sync failed (red), offline (gray). Last successful snapshot keeps showing.
2. **Settings/Onboarding banner** (semi-blocking): `401 Unauthorized` wipes Keychain and routes to onboarding; `404` on the active repo banners "Can't reach `owner/repo`".
3. **Detail-view inline error** (scoped): timeline fetch failure shows "Couldn't load timeline. Retry" at the top of the column without blocking the right rail.

### 8.2 Edge cases — explicit decisions

- **PAT lacks `repo` scope on a private repo** → 200 + empty list, indistinguishable from "no PRs". Mitigation: onboarding does a `GET /repos/{owner}/{repo}` to verify access.
- **Repo renamed on GitHub** → 301 followed once; banner offers to update the stored repo name.
- **PR force-pushed (new `headSha`)** → on next sync, `pr.ciChecks` cleared before new check-runs inserted.
- **Timeline event deleted on GitHub** → on next detail fetch, it's gone from the response → deleted locally. `isSeen` for that event is lost.
- **PR no longer appears in the open list** → flipped to `closed` state, not deleted (user might still have detail open).
- **PR open in detail view when it closes externally** → detail view shows a banner "This PR was closed externally" via reactive update from `@Query`.
- **Future-dated `at` (clock skew)** → relative formatter clamps negative deltas to "just now".
- **Empty repo / first PR ever** → all sections render with `count = 0`. Pills hidden when zero.
- **Massive timeline (>100 events)** → cap at one page; "Load older events" footer button. No automatic pagination.
- **Token rotation** → next request uses the new value; no app restart.
- **Sleep mid-fetch** → in-flight request cancels naturally on `willSleepNotification`; resumes on `didWakeNotification` with a fresh refresh.
- **Two app instances** → relying on macOS single-instance default. Second instance's writes will fail; acceptable for v1.
- **Network offline** → `URLError` → toolbar chip "Offline". Auto-retry on next tick; no manual reachability listener.

### 8.3 Explicitly NOT defended (YAGNI)

- Encrypted Keychain export between Macs
- Multi-account support (one PAT, one viewer)
- GitHub Enterprise hosts
- Custom CA / proxy configuration
- Crash reporting / telemetry

## 9. Testing strategy

### 9.1 `Classifier` — pure-function unit tests (highest priority)

Test matrix covers the six-section taxonomy plus precedence:
- PR I authored, no reviews → `mine`
- PR I authored, CI failed → `attention`
- PR I authored, reviewer requested changes → `attention`
- PR where I'm a requested reviewer, haven't reviewed → `review`
- PR where I'm a requested reviewer, already approved → `involved`
- PR where I commented but wasn't requested → `involved`
- PR with `@me` mention in a comment → `mentions`
- Merged in last 7 days → `recent`
- Merged 8 days ago → not in feed
- Author is me **and** in `attention` → `attention` wins

Plain XCTest, no SwiftData, no network.

### 9.2 `GitHubClient` — `URLProtocol` stub tests

Real captured JSON under `PRTrackerTests/Fixtures/`:
- `validate()` — `user.json`
- `listOpenPRs()` — `pulls_open.json`
- `checkRuns()` — `check_runs.json`
- `participatingNotifications()` — `notifications.json`
- `timeline()` — `timeline_5107.json` (covers commit / review / comment / status / labeled subtypes)
- `304` path → `.notModified`
- `401` → `.unauthorized`
- `403` rate-limit → `.rateLimited(resetAt:)` with parsed reset time

### 9.3 `SyncActor` — SwiftData integration tests

In-memory `ModelContainer`. Cases:
- Empty store + DTO → rows + relationships wired
- Existing store + same DTO with one new comment → exactly one new `TimelineEvent`, others untouched, `isSeen` preserved
- Existing PR + new `headSha` → old `CIRun`s gone, new ones present
- PR present in store but absent from response → marked `closed`, not deleted
- Same `User.login` appearing as author + reviewer + commenter → exactly one `User` row

### 9.4 `isSeen` round-trip

Dedicated test: a sync that re-supplies an existing `TimelineEvent` does not reset `isSeen`. This is the most consequential local invariant — losing it breaks the entire UX.

### 9.5 View tests

`#Preview` for every view with seeded in-memory `ModelContainer` fixtures. These ARE the visual regression suite — eyeballed in Xcode previews. Documented in the project README.

No XCUITests in v1 (the project removed them in the recent commit `9e2e2c2`; reinstating them would slow CI for little value at this scale).

### 9.6 Manual verification checklist

- Toggle dark mode mid-app — colors flip correctly
- Drag window across displays with different scale factors
- Sleep Mac for 1h, wake — sync fires, no duplicate events
- Block github.com via `/etc/hosts` — offline indicator + recovery
- Paste an obviously bad PAT — routing back to onboarding
- Repo with 0 PRs, repo with 50 PRs

### 9.7 Fixture maintenance

`scripts/refresh-fixtures.sh` hits real GitHub with a PAT and saves canonical responses. Run when GitHub schema drifts (rare; we pin `X-GitHub-Api-Version: 2022-11-28`). Fixtures checked in (no PII; uses a public test repo).

### 9.8 CI

None added in v1. Local `xcodebuild test` only.

## 10. Open items deferred to the implementation plan

These are decided in spirit but the writing-plans phase will pin them down:

- Concrete order of build phases (probably: design system → models → keychain + GitHubClient → SyncActor → Classifier → FeedView → PRDetailView → MenuBarExtra → SettingsView → Onboarding)
- Whether to ship a fixture-driven preview-mode app target separate from the live target
- Specific SF Symbol names per icon role
- Exact colors for the `ReviewState` and `CIState` pills (handoff has tokens; mapping may need a small table)
