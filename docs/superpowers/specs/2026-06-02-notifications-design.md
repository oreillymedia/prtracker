# Notifications — Design Spec

**Status:** Approved for plan-writing
**Date:** 2026-06-02
**Branch:** `ui-enhancements`
**Supersedes:** the never-implemented `2026-05-21-notifications-design.md` (deleted in the same commit as this file)

## 1. Goal

Post macOS native notifications for PR activity, with a three-level configurability model:

- **Everything** — all changes on any synced PR.
- **Personal** — any change on a PR the user authored; any new issue-comment on a PR where the user has previously commented; any reply to one of the user's code comments.
- **None** — no notifications.

Independently, the app's two icons (menu-bar and Dock) can each be configured to display a presence indicator (a dot, no count) reflecting whether there are PRs awaiting the user's attention.

Notifications and badging are two orthogonal controls, both in Settings.

## 2. Triggers

### 2.1 Event surface (Everything level)

The following events on any synced PR fire a notification under **Everything**:

| # | Event | Source |
|---|---|---|
| 1 | Issue comment on the PR | `TimelineEvent` with `type == .comment` |
| 2 | Code-review comment | `ReviewComment` |
| 3 | Review submitted (approved / changes-requested / commented) | `TimelineEvent` with `type == .review` |
| 4 | CI **failure** (only) | `CIRun` with `state == .fail` |
| 5 | State change: merged, closed, or reopened (open after non-open) | change in `pr.state` |
| 6 | New commits pushed | change in `pr.headSha` |
| 7 | PR opened (first time seen by the app) | absence of an `"opened_<prID>"` log row |

Explicitly **excluded** even at Everything: reviewer-requested, label/assignee/draft toggles, CI successes.

### 2.2 Personal level

Personal eligibility is per-event:

- **Viewer-authored PRs:** all 7 event kinds above fire.
- **Other PRs:** only two kinds fire —
  - `.codeComment` whose `inReplyToID` resolves to a comment authored by the viewer, AND
  - `.issueComment` on a PR where the viewer has previously commented (issue-level OR code-level — collectively `viewerHasCommented`).
- Reviewer-requested is **not** a personal trigger (deliberate; v1).

### 2.3 No self-notification

If the event's actor (comment author, review author, pushing user, state-change actor, PR opener) equals the viewer's login, the event is filtered out before reaching the level rules. The viewer never sees a banner caused by their own action.

## 3. Aggregation

Per PR, per sync:

- **1 eligible event** → a specific banner for that event (see content table in §6.3).
- **≥2 eligible events** → one combined banner: `"<N> updates on '<PR title>'"`.

Every contributing event still writes its own `NotificationLog` row, so dedup remains correct.

## 4. Suppression while app is frontmost

If `NSApp.isActive == true` at the moment `dispatcher.process` runs, no banners are posted **and no log rows are written**. The next sync (with the app in the background) will fire banners for whatever's still eligible. This matches Q9 (c) — the app-frontmost check, not the per-PR-detail check.

The `NotificationDelegate.willPresent` hook is a secondary check for banners that were queued just before activation.

## 5. Architecture

```
SyncCoordinator.refresh() succeeds
        ↓
NotificationDispatcher.process(repoID:)
        ↓ reads ViewerState (level, badging prefs)
        ↓ short-circuits if level == .none
        ↓ short-circuits if macOS auth ≠ .authorized
        ↓ short-circuits if NSApp.isActive
        ↓ collects candidate events per PR
        ↓ filters via NotificationPolicy.shouldNotify(level:event:pr:viewer:)
        ↓ filters via NotificationLog (per-event surrogate ids)
        ↓ aggregates per-PR (single → specific; ≥2 → aggregate)
        ↓ posts via UNUserNotificationCenter
        ↓ writes NotificationLog rows for each contributing event
        ↓ ctx.save()

BadgeController (independent, reactive)
        ↓ menu-bar icon: renders corner-dot variant when enabled AND attentionCount > 0
        ↓ Dock tile: badgeLabel = "●" when enabled AND attentionCount > 0
```

### 5.1 New files

- `PRTracker/Notifications/NotificationLevel.swift` — the enum.
- `PRTracker/Notifications/NotificationPolicy.swift` — pure rule engine.
- `PRTracker/Notifications/NotificationDispatcher.swift` — orchestration + posting.
- `PRTracker/Notifications/NotificationPoster.swift` — protocol + `UNCenter` impl.
- `PRTracker/Notifications/NotificationDelegate.swift` — click routing, foreground gate.
- `PRTracker/Notifications/NotificationAuthorization.swift` — auth API wrapper + protocol.
- `PRTracker/Notifications/BadgeController.swift` — menu-bar dot + Dock badge driver.
- `PRTracker/Models/NotificationLog.swift` — new `@Model`.

### 5.2 Modified files

- `PRTracker/Models/ViewerState.swift` — add `notificationLevelRaw`, `menuBarBadgeEnabled`, `dockBadgeEnabled`.
- `PRTracker/Models/PullRequest.swift` — add cascading `notificationLogs: [NotificationLog]`.
- `PRTracker/App/PRTrackerApp.swift` — register `NotificationLog` schema; wire `NotificationDelegate`; instantiate dispatcher and `BadgeController`.
- `PRTracker/Sync/SyncCoordinator.swift` — call `await dispatcher.process(repoID:)` after a successful sync; write `badgeController.attentionCount` from feed classification.
- `PRTracker/Views/MenuBar/MenuBarBadge.swift` — replace `count: Int` with `showDot: Bool`.
- `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift` — replace numeric variant with corner-dot variant.
- `PRTracker/Views/Settings/SettingsView.swift` — add a Notifications tab.

## 6. Data model

### 6.1 `NotificationLevel`

```swift
enum NotificationLevel: String, CaseIterable {
    case none, personal, everything
}
```

### 6.2 `ViewerState` additions

```swift
var notificationLevelRaw: String = NotificationLevel.personal.rawValue
var menuBarBadgeEnabled: Bool = true
var dockBadgeEnabled: Bool = true

var notificationLevel: NotificationLevel {
    get { NotificationLevel(rawValue: notificationLevelRaw) ?? .personal }
    set { notificationLevelRaw = newValue.rawValue }
}
```

Defaults: level = **Personal**, both badges **ON**. Existing rows pick up the defaults on the additive SwiftData migration.

### 6.3 `NotificationLog`

```swift
@Model final class NotificationLog {
    @Attribute(.unique) var id: String
    var kind: String        // "comment" | "review" | "ci_failure" | "state_change" | "push" | "opened"
    var notifiedAt: Date
    var pullRequest: PullRequest

    init(id: String, kind: String, notifiedAt: Date, pullRequest: PullRequest) {
        self.id = id; self.kind = kind; self.notifiedAt = notifiedAt; self.pullRequest = pullRequest
    }
}
```

`id` schemes (deterministic, per-event — never per-banner):

| Trigger | id |
|---|---|
| Issue comment | `"comment_\(event.id)"` |
| Code-review comment | `"comment_\(comment.id)"` |
| Review submitted | `"review_\(event.id)"` |
| CI run failure | `"ci_\(run.id)"` |
| State change | `"state_\(pr.id)_\(pr.state.rawValue)"` |
| Push | `"push_\(pr.id)_\(headSha)"` |
| Opened | `"opened_\(pr.id)"` |

### 6.4 `PullRequest` relationship

```swift
@Relationship(deleteRule: .cascade, inverse: \NotificationLog.pullRequest)
var notificationLogs: [NotificationLog] = []
```

Logs disappear with their PR. No standalone retention sweep in v1.

## 7. `NotificationPolicy` (pure)

### 7.1 Inputs

```swift
struct NotificationCandidate {
    enum Kind {
        case issueComment(authorLogin: String, body: String)
        case codeComment(authorLogin: String, inReplyToAuthorLogin: String?, body: String)
        case reviewSubmitted(authorLogin: String, state: ReviewState)
        case ciFailure(runID: String)
        case stateChange(newState: PRState, actorLogin: String?)
        case headPushed(headSha: String, actorLogin: String?)
        case opened(authorLogin: String)
    }
    let kind: Kind
    let prID: String
}

struct PRContext {
    let id: String
    let authorLogin: String
    let viewerHasCommented: Bool   // viewer has at least one issueComment or codeComment on this PR
}
```

### 7.2 Decision

```swift
enum NotificationPolicy {
    static func shouldNotify(level: NotificationLevel,
                             candidate: NotificationCandidate.Kind,
                             pr: PRContext,
                             viewerLogin: String) -> Bool {
        if level == .none { return false }
        if let actor = actorLogin(for: candidate), actor == viewerLogin { return false }
        if level == .everything { return everythingAllows(candidate) }
        return personalAllows(candidate, pr: pr, viewerLogin: viewerLogin)
    }
}
```

### 7.3 `Everything`

```swift
private static func everythingAllows(_ k: NotificationCandidate.Kind) -> Bool {
    switch k {
    case .issueComment, .codeComment, .reviewSubmitted,
         .stateChange, .headPushed, .opened, .ciFailure:
        return true
    }
}
```

### 7.4 `Personal`

```swift
private static func personalAllows(_ k: NotificationCandidate.Kind,
                                   pr: PRContext,
                                   viewerLogin: String) -> Bool {
    let isMyPR = pr.authorLogin == viewerLogin
    if isMyPR { return everythingAllows(k) }
    switch k {
    case .codeComment(_, let inReplyToAuthor, _):
        return inReplyToAuthor == viewerLogin
    case .issueComment:
        return pr.viewerHasCommented
    default:
        return false
    }
}
```

### 7.5 `actorLogin(for:)`

```swift
private static func actorLogin(for k: NotificationCandidate.Kind) -> String? {
    switch k {
    case .issueComment(let a, _): return a
    case .codeComment(let a, _, _): return a
    case .reviewSubmitted(let a, _): return a
    case .stateChange(_, let a), .headPushed(_, let a): return a
    case .opened(let a): return a
    case .ciFailure: return nil
    }
}
```

## 8. `NotificationDispatcher`

### 8.1 Signature

```swift
final class NotificationDispatcher {
    private let modelContainer: ModelContainer
    private let poster: NotificationPoster
    private let appState: AppState
    private let auth: NotificationAuthorizing

    init(modelContainer: ModelContainer,
         poster: NotificationPoster,
         appState: AppState,
         auth: NotificationAuthorizing = NotificationAuthorization()) { … }

    func process(repoID: String) async
    func backfillSilentBaseline() async
}
```

### 8.2 `process(repoID:)` pseudocode

```text
1. Read ViewerState. If level == .none, return.
2. If await auth.currentStatus() != .authorized, return.
3. If await MainActor.run({ NSApp.isActive }), return.
4. Resolve viewerLogin from ViewerState.viewer?.login. If nil, return.
5. Fetch PullRequests for repoID.
6. For each PR:
   a. Build PRContext { id, authorLogin, viewerHasCommented }.
   b. existing = Set(pr.notificationLogs.map(\.id)).
   c. candidates = collectCandidates(pr, existing).
   d. filtered = candidates where:
        NotificationPolicy.shouldNotify(level, candidate.kind, pr: PRContext, viewerLogin)
        AND idFor(candidate) not in existing
   e. if filtered.count == 0: continue
      if filtered.count == 1: content = specificContent(filtered[0], pr)
      else: content = aggregateContent(count: filtered.count, pr)
   f. await poster.post(content)
   g. For each candidate in filtered: insert NotificationLog(id: idFor(candidate), kind: kindFor(candidate), notifiedAt: .now, pullRequest: pr).
7. ctx.save()
```

### 8.3 Candidate collection per PR

| Source | Candidate kind |
|---|---|
| `TimelineEvent` where `type == .comment` AND `"comment_\(event.id)" ∉ existing` | `.issueComment(author, body)` |
| `ReviewComment` where `"comment_\(comment.id)" ∉ existing` | `.codeComment(author, inReplyToAuthor, body)` |
| `TimelineEvent` where `type == .review` AND `"review_\(event.id)" ∉ existing` | `.reviewSubmitted(author, state)` |
| `CIRun` where `state == .fail` AND `"ci_\(run.id)" ∉ existing` | `.ciFailure(run.id)` |
| `pr.state` if `"state_\(prID)_\(pr.state.rawValue)" ∉ existing` AND state ∈ {merged, closed, open-after-non-open} | `.stateChange(state, actor)` |
| `pr.headSha` if `"push_\(prID)_\(headSha)" ∉ existing` | `.headPushed(headSha, actor)` |
| `"opened_\(prID)" ∉ existing` | `.opened(authorLogin)` |

`inReplyToAuthor` is resolved in the dispatcher by looking up the parent `ReviewComment.author.login` via `inReplyToID` (the dispatcher has SwiftData access; the policy does not).

### 8.4 Content builders

| Kind | Title | Body |
|---|---|---|
| `.issueComment` | `<repo> #<n>` | `<author>: <body, ≤200 chars>` |
| `.codeComment` | `<repo> #<n>` | `<author> commented on <file>:<line>: <body, ≤200 chars>` |
| `.reviewSubmitted` | `<repo> #<n>` | `<author> <approved \| requested changes \| reviewed> '<PR title>'` |
| `.ciFailure` | `<repo> #<n>` | `CI failed on '<PR title>'` |
| `.stateChange` | `<repo> #<n>` | `<actor> <merged \| closed \| reopened> '<PR title>'` |
| `.headPushed` | `<repo> #<n>` | `<actor> pushed new commits to '<PR title>'` |
| `.opened` | `<repo> #<n>` | `<author> opened '<PR title>'` |
| aggregate (≥2) | `<repo> #<n>` | `<N> updates on '<PR title>'` |

All content: `threadIdentifier = pr.id`, `userInfo = ["prID": pr.id]`, `sound = .default`.

### 8.5 `backfillSilentBaseline()`

Runs once when the user transitions level from `.none` to `.personal` or `.everything` AND `requestAuthorization` returns `.authorized`. Walks every PR and writes a `NotificationLog` row for every existing event (`comment_`, `review_`, `ci_`, `state_`, `push_`, `opened_`) without posting. Prevents the first post-enable sync from spamming months of history.

## 9. `NotificationPoster`

```swift
protocol NotificationPoster {
    func post(_ content: UNNotificationContent) async
}

struct UNCenterPoster: NotificationPoster {
    func post(_ content: UNNotificationContent) async {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}

final class CapturingPoster: NotificationPoster {   // tests
    var posted: [UNNotificationContent] = []
    func post(_ content: UNNotificationContent) async { posted.append(content) }
}
```

## 10. `NotificationDelegate`

```swift
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        if await MainActor.run(body: { NSApp.isActive }) { return [] }
        return [.banner, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let prID = response.notification.request.content.userInfo["prID"] as? String else { return }
        await MainActor.run {
            appState?.pendingDeepLink = .pr(prID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

Wired in `PRTrackerApp.init`:

```swift
let delegate = NotificationDelegate()
delegate.appState = appState
UNUserNotificationCenter.current().delegate = delegate
self.notificationDelegate = delegate
```

### 10.1 Deep-link routing

`AppState.pendingDeepLink` is observed by `RootView`. On change:
- Find the PR with `id == prID` across visible buckets. Switch to the bucket it lives in, push detail.
- If the PR isn't in any bucket (aged out / closed beyond Recent window): show a brief toast — "That PR is no longer in your feed." — and clear the link.

Cold-launch case: `didReceive` fires after the SwiftUI scene is constructed. `pendingDeepLink` is set; `RootView` consumes it on first appearance.

## 11. `NotificationAuthorization`

```swift
protocol NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> UNAuthorizationStatus
}

struct NotificationAuthorization: NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func requestAuthorization() async -> UNAuthorizationStatus {
        _ = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        return await currentStatus()
    }
}
```

### 11.1 First-launch flow

In `RootView.onAppear` (idempotent):

```text
1. status = await auth.currentStatus()
2. If vs.notificationLevel == .none: no-op.
3. If status == .notDetermined:
     status = await auth.requestAuthorization()
4. If status == .authorized AND no NotificationLog rows exist yet for this ModelContainer:
     await dispatcher.backfillSilentBaseline()
```

Covers all paths into "authorized with empty log":

- Fresh install (default `.personal`, `.notDetermined` → request → grant) → backfill.
- Existing-user upgrade (post-migration default `.personal`, prior status `.notDetermined`) → request → grant → backfill.
- "Denied earlier, granted later in System Settings" (status flips to `.authorized` without going through step 3) → log is still empty → backfill.

The "empty log" guard makes the step idempotent: once a baseline exists, this never re-runs accidentally on subsequent launches.

### 11.2 Auth revoked externally

`dispatcher.process` checks `currentStatus()` every run and short-circuits when not `.authorized`. Posts silently stop. The Settings tab re-reads `currentStatus()` on appear and surfaces the hint when status is `.denied`.

## 12. `BadgeController`

```swift
@Observable
final class BadgeController {
    var attentionCount: Int = 0
    var menuBarEnabled: Bool = true
    var dockEnabled: Bool = true

    var menuBarShowsDot: Bool { menuBarEnabled && attentionCount > 0 }
    var dockShowsBadge: Bool { dockEnabled && attentionCount > 0 }

    func apply() {
        NSApp.dockTile.badgeLabel = dockShowsBadge ? "●" : nil
    }
}
```

### 12.1 Menu-bar icon

`MenuBarIconRenderer.image(showDot:)` returns an `NSImage` with:
- the existing base glyph, and
- when `showDot == true`, a 7×7 px filled circle in `Tokens.accent` with a 1.5 px stroke matching the menu-bar background, positioned in the upper-right corner.

`MenuBarBadge.count: Int` becomes `MenuBarBadge.showDot: Bool`, driven by `BadgeController.menuBarShowsDot`. The numeric-rendering code path is removed.

### 12.2 Dock tile

`NSApp.dockTile.badgeLabel = "●"` when `dockShowsBadge` is true, `nil` otherwise. Set on every `apply()` and cleared in `applicationWillTerminate`.

### 12.3 Wiring

- Instantiate once in `PRTrackerApp.init`.
- `SyncCoordinator` writes `attentionCount` after each successful sync (the value already exists for the current numeric badge; the source doesn't change).
- `SettingsView`'s toggles write to `vs.menuBarBadgeEnabled` / `vs.dockBadgeEnabled`; an `onChange` bridge mirrors them onto `BadgeController` and calls `apply()`.

## 13. Settings UI

A new **Notifications** tab in the existing `TabView`, between General and Account:

```
Notify me about
  ◯ Everything   All comments, reviews, CI failures, commits, and state changes
  ◉ Personal     PRs you authored, replies to your comments
  ◯ None         No notifications

  [conditional]  macOS notifications are disabled for PR Tracker.
                 Enable in System Settings → Notifications → PR Tracker.

Badging
  [✓] Show indicator on menu-bar icon
  [✓] Show indicator on Dock icon
```

### 13.1 Level-change handler

```text
1. Save newValue to vs.notificationLevelRaw.
2. If newValue == .none: done.
3. Else:
   a. status = await auth.currentStatus()
   b. previousLevel was .none?  → needsBaseline = true   (capture before save)
   c. If status == .notDetermined:
        status = await auth.requestAuthorization()
   d. If status == .authorized AND needsBaseline:
        await dispatcher.backfillSilentBaseline()
   e. Compute showAuthDeniedHint = (status == .denied)
```

Picker stays on the user's choice even when auth is denied. The hint text below it tells them how to fix it.

### 13.2 Badge-toggle handler

Each toggle writes through to `vs`, saves, and calls `BadgeController.apply()` to re-render.

### 13.3 Tab frame

The existing TabView frame (`.frame(width: 480, height: 280)`) accommodates the new tab without resizing.

## 14. Sandbox & entitlements

App is already sandboxed. `UserNotifications` requires no additional entitlement. `NSApp.dockTile.badgeLabel` requires nothing extra. No `Info.plist` changes.

## 15. Testing

### 15.1 `NotificationPolicyTests` (pure)

- **`.none`**: every kind → `false`.
- **`.everything`**:
  - Each of the 7 kinds with non-viewer actor → `true`.
  - Same with `actor == viewerLogin` → `false`.
- **`.personal`, viewer is author**: all 7 kinds (non-viewer actor) → `true`; viewer actor → `false`.
- **`.personal`, viewer is not author**:
  - `.codeComment` with `inReplyToAuthor == viewerLogin` → `true`.
  - `.codeComment` with `inReplyToAuthor != viewerLogin` → `false`.
  - `.codeComment` with `inReplyToAuthor == nil` (top-level) → `false`.
  - `.issueComment` with `viewerHasCommented == true` → `true`.
  - `.issueComment` with `viewerHasCommented == false` → `false`.
  - `.reviewSubmitted`, `.ciFailure`, `.stateChange`, `.headPushed`, `.opened` → all `false`.

### 15.2 `NotificationDispatcherTests` (in-memory SwiftData + `CapturingPoster`)

- Single new comment on a feed-visible PR → 1 `post`; 1 log row.
- 2 comments + 1 CI failure on one PR in one sync → 1 `post` with `"3 updates on '<title>'"`; 3 log rows.
- Repeat `process` with no new data → 0 posts; log row count unchanged.
- `backfillSilentBaseline` on a PR with existing events → 0 posts; one log row per event.
- App frontmost (`appState.appIsFrontmost == true`) → 0 posts AND 0 log rows.
- Auth status `.denied` → 0 posts, 0 log rows.
- Self-actor events → 0 posts.
- Logged `state_<prID>_merged` then re-process with same merged state → 0 posts.
- Force-push: new SHA + previously-logged CI failures from old SHA → push fires; CI doesn't refire.

### 15.3 `BadgeControllerTests`

- Enabled + attention 0 → dot off, dock label nil.
- Enabled + attention 3 → dot on, dock label `"●"` (iff `dockEnabled`).
- Toggle `dockEnabled` off while attention 3 → dock label nil; menu-bar unchanged.

### 15.4 Manual smoke

- Fresh install → permission prompt → grant → comment on a real PR → banner with correct title/body.
- Switch level to Everything → CI failure or push → banner fires.
- Switch to None → no banners.
- Toggle menu-bar badge off → dot disappears with attention > 0.
- Toggle Dock badge off → Dock dot disappears.
- Click banner with app quit → app launches, lands on PR detail.
- Click banner with app running → app focuses, detail switches.
- App frontmost, new event arrives → no banner; switch app away, new event → banner.
- Revoke auth in System Settings → Settings tab shows the hint on next visit.

## 16. Risks & open items

- **First-launch prompt is intrusive.** Default `.personal` shows the macOS authorization prompt on first launch (fresh install AND existing-user upgrade). Acceptable per Q7 (a); mitigation deferred.
- **`viewerHasCommented` is O(PR × comments).** Cheap per-PR; if feed sizes grow large, denormalize onto `PullRequest`.
- **Aggregate banners hide author identity.** Bursts of ≥2 events show "N updates on '<title>'" with no per-event detail. Acceptable per Q8 (b).
- **`NotificationLog` growth.** One row per event ever notified, capped only by PR-delete cascade. Likely fine for typical use; if it surfaces, add an age-based sweep for closed PRs.
- **App must be running.** No notifications when the app is fully quit. Consistent with the menu-bar-app model.
- **No count distinction in badges.** Users lose the "is this 1 thing or 5?" signal from the menu-bar number. Accepted explicitly in Section 5 discussion.

## 17. Out of scope (v1)

- Per-event-type opt-outs within a level.
- Notification action buttons (Reply, Mark as read).
- Custom sounds.
- Per-PR muting.
- Quiet hours / DND integration.
- Critical/time-sensitive notifications.
- Background push from a server.
- Numeric badges on either icon.
- Reviewer-requested as a trigger.
- Notification preferences sync across devices.
