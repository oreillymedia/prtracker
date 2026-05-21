# macOS Native Notifications — Design Spec

**Status:** Approved for plan-writing
**Date:** 2026-05-21
**Branch:** `notifications`

## 1. Goal

Post macOS native notification banners (`UserNotifications` framework) for new activity on PRs the user is involved in. Three trigger types: new comments / @mentions, CI failures on the user's own PRs, and PR state changes (merged / closed / reopened). One notification per event. Clicking a notification opens the app and routes to that PR's detail.

Notifications are off by default and gated by a Settings toggle that triggers macOS authorization on enablement.

## 2. Scope boundaries

**In scope:** New comments (issue-level and code-level review comments), CI failures on the viewer's own PRs, PR state transitions on PRs visible in the feed. Click-to-open routing. Per-PR thread grouping. Suppression when the user is already viewing the PR.

**Out of scope:** Notification action buttons (Reply / Mark Read from the banner), critical / time-sensitive notifications, custom sounds, badge counts on the menu-bar icon (already handled by `MenuBarBadge`), in-banner image attachments, requesting permission outside of the user explicitly flipping the Settings toggle.

## 3. Triggers

A PR is eligible to trigger notifications if and only if it currently lands in any non-`.all` Classifier bucket (`attention`, `review`, `mentions`, `mine`, `involved`, `recent`). PRs that don't pass the classifier produce no notifications.

| # | Trigger | Condition | Body content |
|---|---------|-----------|--------------|
| 1 | New comment | `TimelineEvent` of `type == .comment` inserted this sync AND not in `NotificationLog` AND PR is in any bucket | `<author>: <body, truncated to 200 chars>` |
| 2 | New code comment | `ReviewComment` inserted this sync AND not in `NotificationLog` AND PR is in any bucket | `<author>: <body, truncated to 200 chars>` |
| 3 | CI failure on my PR | `CIRun` with `state == .fail` AND not in `NotificationLog` AND `pr.author.login == viewer.login` | `<N> check(s) failed on '<PR title>'` (count aggregated across the same PR's failing runs not yet logged) |
| 4 | State change | `pr.state` differs from any log entry `"state_<prID>_<currentState>"` AND new state ∈ {merged, closed, open (reopened)} AND the viewer has standing on the PR (see §3.1) | `<actor> <verb> '<PR title>'` |

Comment + code comment cases use the same notification kind (`"comment"`) and content template. They're separated above only because they live in different SwiftData entities.

### 3.1 Viewer standing (state-change eligibility)

A state-change notification fires only if the viewer has *standing* on the PR. Standing is true when any of:

- The PR currently classifies into any non-`.all` Classifier bucket (`Classifier.section(...) != nil`), OR
- `pr.author.login == viewer.login`, OR
- `pr.reviewers.contains(where: { $0.user.login == viewer.login })`, OR
- Any timeline event has `actor?.login == viewer.login` (i.e. the viewer commented).

This rule means: PRs the viewer authored, reviewed, commented on, or that currently appear in their feed will surface state-change banners. Random closures on unrelated PRs in the same repo do not.

### 3.2 CI failure aggregation

When a single sync produces multiple newly-failed `CIRun` rows on the same PR, post **one combined notification** ("`<N>` checks failed on '<title>'") and log **all** the contributing run ids in `NotificationLog`. A subsequent sync that uncovers more failed runs (e.g. on a new head SHA) posts a separate notification for the new failures only.

## 4. Architecture

```
SyncCoordinator.refresh() succeeds
    ↓
NotificationDispatcher.process(repoID:)
    ↓ reads PRs, walks feed-visible ones
    ↓ collects candidate events / runs / state changes
    ↓ filters via NotificationLog (single per-PR fetch)
    ↓ posts via UNUserNotificationCenter.add(_:)
    ↓ inserts NotificationLog rows for posted notifications
    ↓ saves
```

### New components

- `PRTracker/Notifications/NotificationDispatcher.swift` — post-sync delta computer + poster. No stored state; reads the SwiftData container, posts banners, writes log rows.
- `PRTracker/Notifications/NotificationDelegate.swift` — `UNUserNotificationCenterDelegate`. Handles click routing and foreground presentation.
- `PRTracker/Notifications/NotificationAuthorization.swift` — wraps `requestAuthorization(options:)`, `getNotificationSettings()`. Used by the Settings toggle.
- `PRTracker/Models/NotificationLog.swift` — new `@Model`.

### Modified components

- `PRTracker/Models/PullRequest.swift` — add cascade relationship `notificationLogs: [NotificationLog]`.
- `PRTracker/App/PRTrackerApp.swift` — register `NotificationLog.self` in the schema; wire `NotificationDelegate` to `UNUserNotificationCenter.current().delegate`.
- `PRTracker/Sync/SyncCoordinator.swift` — hold a `NotificationDispatcher`; invoke `await dispatcher.process(repoID:)` after `lastSyncAt = .now` in `refresh()`.
- `PRTracker/Models/ViewerState.swift` — add `var notificationsEnabled: Bool = false`.
- `PRTracker/Views/Settings/SettingsView.swift` — add "Show notifications" Toggle in the General tab.

## 5. Data model

### New: `NotificationLog`

```swift
@Model final class NotificationLog {
    @Attribute(.unique) var id: String     // dedup key, see id schemes below
    var kind: String                       // "comment" | "ci_failure" | "state_change"
    var notifiedAt: Date
    var pullRequest: PullRequest

    init(id: String, kind: String, notifiedAt: Date, pullRequest: PullRequest) {
        self.id = id; self.kind = kind; self.notifiedAt = notifiedAt; self.pullRequest = pullRequest
    }
}
```

### `id` schemes (deterministic, prefixed by kind)

| Trigger | id |
|---|---|
| `TimelineEvent` comment | `"comment_\(event.id)"` |
| `ReviewComment` | `"comment_\(comment.id)"` |
| `CIRun` failure | `"ci_\(ciRun.id)"` |
| State change | `"state_\(pr.id)_\(pr.state.rawValue)"` |

Comment and code-comment ids both start with `"comment_"` — the underlying `event.id` / `comment.id` are themselves globally unique surrogates, so collisions are impossible.

### `PullRequest` relationship

```swift
@Relationship(deleteRule: .cascade, inverse: \NotificationLog.pullRequest)
var notificationLogs: [NotificationLog] = []
```

Cascade ensures logs disappear with the PR (closes the long-tail growth path).

### `ViewerState`

```swift
var notificationsEnabled: Bool = false
```

Defaults to false on existing installs (additive SwiftData migration).

## 6. NotificationDispatcher

Initialized once in `PRTrackerApp.init` with the model container, attached to `SyncCoordinator`. The actor signature:

```swift
final class NotificationDispatcher {
    private let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }

    func process(repoID: String) async { … }
    func backfillSilentBaseline() async { … }   // run once on toggle-on
}
```

### `process(repoID:)` pseudocode

```text
1. Read enabled flag from ViewerState; if false, return.
2. Read authorization status via getNotificationSettings(); if not .authorized, return.
3. Fetch all PullRequests in repoID. Filter to feed-visible (run Classifier with current viewer login; non-nil bucket).
4. Determine viewer login from ViewerState.viewer.login.
5. For each visible PR:
   a. Build a Set<String> of existing log ids: pr.notificationLogs.map(\.id).
   b. For each TimelineEvent in pr.timeline where type == .comment:
      candidate id = "comment_\(event.id)"; if not in set, post + insert log.
   c. For each ReviewComment in pr.reviewComments:
      candidate id = "comment_\(comment.id)"; if not in set, post + insert log.
   d. Collect all CIRuns where state == .fail AND pr.author.login == viewerLogin AND "ci_\(run.id)" not in set.
      If the collection is non-empty: post ONE combined notification ("<N> checks failed on '<title>'") and insert log rows for every contributing run id.
   e. State change: only proceed if viewer has standing on this PR (see §3.1).
      candidate id = "state_\(pr.id)_\(pr.state.rawValue)"; if not in set AND state ∈ {merged, closed, open (last logged state was non-open)}, post + insert log.
6. ctx.save().
```

### `backfillSilentBaseline()` pseudocode

Runs once when the user grants notification authorization for the first time (toggle flips on AND `requestAuthorization` returns `.authorized`).

```text
1. Fetch all PullRequests.
2. For each PR:
   - For each TimelineEvent where type == .comment: insert "comment_<id>" log row.
   - For each ReviewComment: insert "comment_<id>" log row.
   - For each CIRun where state == .fail: insert "ci_<id>" log row.
   - Insert "state_<prID>_<currentState>" log row.
3. ctx.save().
```

After backfill, only events that arrive on subsequent syncs trigger notifications.

### Content building (per trigger)

```swift
private func contentForComment(pr: PullRequest, actor: User?, body: String) -> UNNotificationContent {
    let c = UNMutableNotificationContent()
    c.title = "\(pr.repo.id) #\(pr.number)"
    c.body = "\(actor?.name ?? actor?.login ?? "Someone"): \(body.prefix(200))"
    c.sound = .default
    c.threadIdentifier = pr.id
    c.userInfo = ["prID": pr.id, "kind": "comment"]
    return c
}
```

(Analogous helpers for CI failure and state change. State-change verb table: `.merged` → "merged", `.closed` → "closed", `.open` → "reopened".)

## 7. Click routing (`NotificationDelegate`)

```swift
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        // Suppress banner when the user is already viewing this PR.
        let prID = notification.request.content.userInfo["prID"] as? String
        if let prID, await MainActor.run(body: { appState?.selectedPRID == prID }) {
            return []
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let prID = response.notification.request.content.userInfo["prID"] as? String else { return }
        await MainActor.run {
            appState?.selectedPRID = prID
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

Wired in `PRTrackerApp.init`:

```swift
let delegate = NotificationDelegate()
delegate.appState = self.appState
UNUserNotificationCenter.current().delegate = delegate
self.notificationDelegate = delegate   // retain
```

If the app is not running when a notification is clicked, macOS launches it. `selectedPRID` is set after the app boots; `RootView` already routes to the correct detail when `selectedPRID` is non-nil.

## 8. Settings UI

Inside the existing General tab's `VStack(alignment: .leading, spacing: 14)`:

```swift
Toggle("Show notifications", isOn: Binding(
    get: { vs.notificationsEnabled },
    set: { newValue in
        Task { await handleToggle(newValue) }
    }))
if vs.notificationsEnabled && lastAuthDenied {
    Text("Enable in System Settings → Notifications → PR Tracker.")
        .font(.system(size: 11))
        .foregroundStyle(Tokens.textFaint)
}
```

`handleToggle(_:)`:

```text
1. If newValue == false: set vs.notificationsEnabled = false; save; return.
2. Call NotificationAuthorization.requestAuthorization().
3. If granted:
   a. Set vs.notificationsEnabled = true; save.
   b. Call dispatcher.backfillSilentBaseline().
4. If denied:
   a. Keep vs.notificationsEnabled = false; surface help text.
```

## 9. Authorization helper

```swift
enum NotificationAuthorization {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch { return false }
    }

    static func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
```

`process(repoID:)` calls `currentStatus()` at the top and bails if not `.authorized` (covers the case where the user revoked permission in System Settings after enabling in-app).

## 10. Sandbox & entitlements

App is already sandboxed (`com.apple.security.app-sandbox = true`). `UserNotifications` requires no additional entitlement. No `info.plist` keys to add (authorization is the sole gate).

## 11. Testing

**Unit tests (new):**

- `NotificationDispatcherTests` — given a fixture PR with synthetic timeline events / CIRuns, verify:
  - `process` posts the expected count of notifications and writes log rows.
  - Subsequent calls with no new content post zero notifications.
  - `backfillSilentBaseline` inserts log rows but doesn't post (verify via a mock `UserNotifications` poster — see below).
  - State change from `.open` → `.merged` posts; second call with state still `.merged` posts zero.
  - CI failure on a PR where viewer ≠ author posts zero.

Mock `UserNotifications`: inject a `NotificationPoster` protocol into the dispatcher:

```swift
protocol NotificationPoster { func post(content: UNNotificationContent) async }
struct UNCenterPoster: NotificationPoster {
    func post(content: UNNotificationContent) async {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
final class CapturingPoster: NotificationPoster {
    var posted: [UNNotificationContent] = []
    func post(content: UNNotificationContent) async { posted.append(content) }
}
```

Production uses `UNCenterPoster`; tests use `CapturingPoster`.

**Manual smoke (not automatable):**

- Toggle Settings → Show notifications → grant authorization → confirm no avalanche.
- Wait for a real PR comment to land → notification appears with the correct title/body.
- Click notification → app activates and detail pane shows that PR.
- Open the same PR's detail → trigger another comment → no banner (suppression works).
- Revoke permission in System Settings → toggle the in-app toggle off → no further posts.
- Toggle off and on again → no avalanche on re-enable (baseline backfill protects).

## 12. Risks & open items

- **Authorization revoked externally.** If the user revokes in System Settings, the in-app toggle still reads "on" until the next launch. `currentStatus()` check in `process` prevents posting silently — banners just stop. We could surface a status warning in Settings on each app launch, but defer that polish.
- **Notification volume during a sync burst.** If a sync detects 20 new comments at once, the user sees 20 banners stacked. macOS groups them by `threadIdentifier = prID`, which mitigates per-PR. Cross-PR bursts are still loud. Deferred mitigation (digest fallback above N events per sync) is out of scope for v1.
- **Notification storage growth.** `NotificationLog` rows accumulate. Cascade on PR deletion is the only cleanup. For long-lived apps tracking thousands of PRs over months, the log could reach 10K+ rows. SwiftData handles that comfortably; revisit if it becomes a real issue.
- **Timezone-sensitive state-change detection.** State changes are tracked via the existence of the `"state_<id>_<state>"` log row, not a timestamp comparison, so timezones don't affect correctness.
- **App must be running for sync-driven posts.** No background sync without the app open. Acceptable per "always running in menu bar" UX. If the user fully quits, no notifications until they relaunch.

## 13. Out of scope (intentionally not covered)

- Critical / time-sensitive notifications (require `com.apple.developer.usernotifications.critical-alerts` entitlement and special UI treatment)
- Notification action buttons ("Reply", "Mark as read" from banner)
- Custom notification sounds beyond `.default`
- Per-PR notification muting
- Quiet hours / Do Not Disturb integration (system handles automatically)
- Notification preferences per trigger type (granular on/off — global toggle only for v1)
- Background push from a server (the app polls)
- Reviewer-requested trigger (deliberately excluded per brainstorming Q1)
