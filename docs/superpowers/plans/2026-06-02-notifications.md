# Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a three-level notification system (Everything / Personal / None) with independently configurable menu-bar and Dock badge dots, per the design at `docs/superpowers/specs/2026-06-02-notifications-design.md`.

**Architecture:** A pure `NotificationPolicy` decides whether a candidate event triggers a banner. `NotificationDispatcher` orchestrates per-sync: collects candidates from SwiftData, asks the policy, aggregates per-PR, posts via an injectable `NotificationPoster`, writes `NotificationLog` rows for dedup. `BadgeController` drives the menu-bar dot and Dock tile from the existing attention count, gated by per-toggle settings. Wiring lives in `PRTrackerApp`/`SyncCoordinator`/`RootView`.

**Tech Stack:** Swift, SwiftUI, SwiftData, AppKit (`UserNotifications`, `NSApp.dockTile`), Swift Testing.

---

## File Structure

### New files

| Path | Purpose |
|---|---|
| `PRTracker/Notifications/NotificationLevel.swift` | The `NotificationLevel` enum. |
| `PRTracker/Notifications/NotificationCandidate.swift` | `NotificationCandidate` + `PRContext` value types used by the policy. |
| `PRTracker/Notifications/NotificationPolicy.swift` | Pure rule engine. |
| `PRTracker/Notifications/NotificationPoster.swift` | Protocol + `UNCenterPoster` impl. |
| `PRTracker/Notifications/NotificationAuthorization.swift` | Protocol + `UNUserNotificationCenter` wrapper. |
| `PRTracker/Notifications/AppActivityProbing.swift` | Protocol + impl that wraps `NSApp.isActive`. |
| `PRTracker/Notifications/NotificationDispatcher.swift` | Orchestration, content builders, baseline backfill. |
| `PRTracker/Notifications/NotificationDelegate.swift` | `UNUserNotificationCenterDelegate` (click routing + foreground gate). |
| `PRTracker/Notifications/BadgeController.swift` | Reactive menu-bar / Dock dot driver. |
| `PRTracker/Models/NotificationLog.swift` | `@Model` for dedup rows. |
| `PRTrackerTests/Notifications/NotificationPolicyTests.swift` | Pure-function rules. |
| `PRTrackerTests/Notifications/NotificationDispatcherTests.swift` | Dispatcher behavior against in-memory SwiftData + capturing poster. |
| `PRTrackerTests/Notifications/BadgeControllerTests.swift` | Toggle / attention-count behavior. |
| `PRTrackerTests/Notifications/Fakes.swift` | `CapturingPoster`, `StubAuth`, `StubActivityProbe`. |

### Modified files

| Path | Change |
|---|---|
| `PRTracker/Models/ViewerState.swift` | Add `notificationLevelRaw`, `menuBarBadgeEnabled`, `dockBadgeEnabled` (with defaults). |
| `PRTracker/Models/PullRequest.swift` | Add cascading `notificationLogs: [NotificationLog]`. |
| `PRTracker/Models/CIRun.swift` | Add `checkRunID: Int?`. |
| `PRTracker/GitHub/DTOs.swift` | Add `id: Int` to `CheckRunDTO`. |
| `PRTracker/Sync/SyncActor.swift` | Populate `CIRun.checkRunID` from DTO. |
| `PRTracker/Sync/SyncCoordinator.swift` | Call `await dispatcher.process(repoID:)` after refresh; update badge controller attention count. |
| `PRTracker/App/PRTrackerApp.swift` | Register `NotificationLog` schema; build dispatcher + delegate + badge controller; replace `MenuBarBadge` with `BadgeController`. |
| `PRTracker/App/RootView.swift` | First-launch auth flow (request + optional baseline backfill). |
| `PRTracker/Views/MenuBar/MenuBarBadge.swift` | Replace numeric `count` with `showDot: Bool` driven by `BadgeController`. |
| `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift` | Replace numeric badge with corner-dot overlay. |
| `PRTracker/Views/MenuBar/MenuBarContentView.swift` | Drive `BadgeController.attentionCount` instead of `badge.count`. |
| `PRTracker/Views/Settings/SettingsView.swift` | Add a Notifications tab. |
| `PRTrackerTests/Helpers/ModelContainerHelper.swift` | Add `NotificationLog.self` to the schema. |

---

## Conventions

- **Tests use Swift Testing** (`import Testing`, `@Suite struct`, `@Test`, `#expect`).
- **Build & test command:** `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -50`. To run a single test, append `-only-testing:PRTrackerTests/<SuiteName>/<testName>`.
- **Commit after every passing task** with a `feat:` / `chore:` / `test:` prefix matching the recent history.
- All new files start with the necessary `import` lines; no implicit globals.

---

## Task 1 — `NotificationLevel` enum + `ViewerState` migration

**Files:**
- Create: `PRTracker/Notifications/NotificationLevel.swift`
- Modify: `PRTracker/Models/ViewerState.swift`

- [ ] **Step 1: Create the enum**

Write `PRTracker/Notifications/NotificationLevel.swift`:

```swift
import Foundation

enum NotificationLevel: String, CaseIterable {
    case none, personal, everything
}
```

- [ ] **Step 2: Extend `ViewerState`**

Open `PRTracker/Models/ViewerState.swift`. Add the three properties + the `notificationLevel` computed accessor. Update `init` to accept defaults. Final file should look like:

```swift
import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var activeRepoID: String?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool
    var themePreferenceRaw: String = "system"
    var notificationLevelRaw: String = NotificationLevel.personal.rawValue
    var menuBarBadgeEnabled: Bool = true
    var dockBadgeEnabled: Bool = true

    enum ThemePreference: String { case system, light, dark }
    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    var notificationLevel: NotificationLevel {
        get { NotificationLevel(rawValue: notificationLevelRaw) ?? .personal }
        set { notificationLevelRaw = newValue.rawValue }
    }

    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system", notificationLevelRaw: String = NotificationLevel.personal.rawValue, menuBarBadgeEnabled: Bool = true, dockBadgeEnabled: Bool = true) {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
        self.notificationLevelRaw = notificationLevelRaw
        self.menuBarBadgeEnabled = menuBarBadgeEnabled
        self.dockBadgeEnabled = dockBadgeEnabled
    }
}
```

The new properties have default values, so the additive SwiftData migration is transparent.

- [ ] **Step 3: Build to verify compile**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Notifications/NotificationLevel.swift PRTracker/Models/ViewerState.swift
git commit -m "feat(notifications): add NotificationLevel + ViewerState fields"
```

---

## Task 2 — `NotificationLog` model + `PullRequest` relationship + schema

**Files:**
- Create: `PRTracker/Models/NotificationLog.swift`
- Modify: `PRTracker/Models/PullRequest.swift`
- Modify: `PRTracker/App/PRTrackerApp.swift` (schema registration only)
- Modify: `PRTrackerTests/Helpers/ModelContainerHelper.swift`

- [ ] **Step 1: Create the model**

Write `PRTracker/Models/NotificationLog.swift`:

```swift
import Foundation
import SwiftData

@Model
final class NotificationLog {
    @Attribute(.unique) var id: String
    var kind: String
    var notifiedAt: Date
    var pullRequest: PullRequest

    init(id: String, kind: String, notifiedAt: Date, pullRequest: PullRequest) {
        self.id = id
        self.kind = kind
        self.notifiedAt = notifiedAt
        self.pullRequest = pullRequest
    }
}
```

- [ ] **Step 2: Add the inverse relationship on `PullRequest`**

In `PRTracker/Models/PullRequest.swift`, append a new relationship after the existing `reviewComments` relationship (around line 48):

```swift
    @Relationship(deleteRule: .cascade, inverse: \NotificationLog.pullRequest)
    var notificationLogs: [NotificationLog] = []
```

- [ ] **Step 3: Register in app schema**

In `PRTracker/App/PRTrackerApp.swift`, find the `Schema([...])` array (around line 17) and add `NotificationLog.self`:

```swift
let schema = Schema([
    User.self, Repo.self, PullRequest.self, TimelineEvent.self,
    Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
    ReviewComment.self, NotificationLog.self,
])
```

- [ ] **Step 4: Register in test schema**

In `PRTrackerTests/Helpers/ModelContainerHelper.swift`, add `NotificationLog.self` to the same array:

```swift
let schema = Schema([
    User.self, Repo.self, PullRequest.self, TimelineEvent.self,
    Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
    ReviewComment.self, NotificationLog.self,
])
```

- [ ] **Step 5: Build + run existing tests to verify nothing breaks**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Models/NotificationLog.swift PRTracker/Models/PullRequest.swift PRTracker/App/PRTrackerApp.swift PRTrackerTests/Helpers/ModelContainerHelper.swift
git commit -m "feat(notifications): add NotificationLog model + PullRequest cascade"
```

---

## Task 3 — Stable check-run id on `CIRun`

**Why:** `CIRun` rows are deleted + recreated every sync, so we can't use a SwiftData surrogate. We persist GitHub's numeric `id` so the dispatcher can dedup CI-failure notifications across syncs.

**Files:**
- Modify: `PRTracker/GitHub/DTOs.swift`
- Modify: `PRTracker/Models/CIRun.swift`
- Modify: `PRTracker/Sync/SyncActor.swift`
- Modify: `PRTrackerTests/Sync/SyncActorTests.swift` (new test)

- [ ] **Step 1: Add the test (failing)**

Append to `PRTrackerTests/Sync/SyncActorTests.swift` (inside the `@Suite struct SyncActorTests`):

```swift
@Test func upsertCIChecksStoresCheckRunID() async throws {
    let (container, repo) = try setup()
    let actor = SyncActor(modelContainer: container)
    try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)

    let json = """
    {"total_count":1,"check_runs":[
      {"id":987654321,"name":"build","status":"completed","conclusion":"failure",
       "started_at":"2026-04-23T10:00:00Z","completed_at":"2026-04-23T10:05:00Z"}
    ]}
    """
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let dto = try d.decode(CheckRunsResponseDTO.self, from: json.data(using: .utf8)!)
    try await actor.upsertCIChecks(prID: "PR_5107", dto: dto)

    let ctx = ModelContext(container)
    let runs = try ctx.fetch(FetchDescriptor<CIRun>())
    #expect(runs.count == 1)
    #expect(runs[0].checkRunID == 987654321)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SyncActorTests/upsertCIChecksStoresCheckRunID 2>&1 | tail -30`
Expected: COMPILE ERROR (`checkRunID` doesn't exist on `CIRun`, `id` doesn't exist on `CheckRunDTO`).

- [ ] **Step 3: Add `id` to `CheckRunDTO`**

In `PRTracker/GitHub/DTOs.swift`, modify `CheckRunDTO`:

```swift
nonisolated struct CheckRunDTO: Decodable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let started_at: Date?
    let completed_at: Date?
}
```

- [ ] **Step 4: Add `checkRunID` to `CIRun`**

Rewrite `PRTracker/Models/CIRun.swift`:

```swift
import Foundation
import SwiftData

@Model
final class CIRun {
    var checkRunID: Int?
    var name: String
    var stateRaw: String
    var durationSeconds: Int?
    var pr: PullRequest

    var state: CIState {
        get { CIState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(checkRunID: Int? = nil, name: String, state: CIState, pr: PullRequest, durationSeconds: Int? = nil) {
        self.checkRunID = checkRunID
        self.name = name
        self.stateRaw = state.rawValue
        self.pr = pr
        self.durationSeconds = durationSeconds
    }
}
```

- [ ] **Step 5: Pass `checkRunID` through `SyncActor.upsertCIChecks`**

In `PRTracker/Sync/SyncActor.swift`, around line 139, update the `ctx.insert(CIRun(...))` call:

```swift
ctx.insert(CIRun(checkRunID: r.id, name: r.name, state: state, pr: pr, durationSeconds: dur))
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SyncActorTests/upsertCIChecksStoresCheckRunID 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 7: Run all tests to verify nothing regressed**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: all tests pass (existing `SyncActor` tests included).

- [ ] **Step 8: Commit**

```bash
git add PRTracker/GitHub/DTOs.swift PRTracker/Models/CIRun.swift PRTracker/Sync/SyncActor.swift PRTrackerTests/Sync/SyncActorTests.swift
git commit -m "feat(ci): persist GitHub check-run id on CIRun"
```

---

## Task 4 — `NotificationCandidate` + `PRContext` value types

**Files:**
- Create: `PRTracker/Notifications/NotificationCandidate.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

struct NotificationCandidate {
    enum Kind {
        case issueComment(authorLogin: String, body: String)
        case codeComment(authorLogin: String, inReplyToAuthorLogin: String?, body: String, path: String, line: Int?)
        case reviewSubmitted(authorLogin: String, state: ReviewState)
        case ciFailure(runID: Int)
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
    /// True when the viewer has authored at least one `TimelineEvent.comment` or `ReviewComment` on this PR.
    let viewerHasCommented: Bool
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Notifications/NotificationCandidate.swift
git commit -m "feat(notifications): NotificationCandidate + PRContext value types"
```

---

## Task 5 — `NotificationPolicy` (pure rule engine) + tests

**Files:**
- Create: `PRTracker/Notifications/NotificationPolicy.swift`
- Create: `PRTrackerTests/Notifications/NotificationPolicyTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `PRTrackerTests/Notifications/NotificationPolicyTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct NotificationPolicyTests {
    private let me = "alex"
    private let other = "iris"

    private func ctx(author: String = "iris", viewerCommented: Bool = false) -> PRContext {
        PRContext(id: "PR_1", authorLogin: author, viewerHasCommented: viewerCommented)
    }

    // MARK: level == .none

    @Test func noneNeverFires() {
        let c = ctx()
        #expect(NotificationPolicy.shouldNotify(level: .none, candidate: .issueComment(authorLogin: other, body: "hi"), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .none, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me) == false)
    }

    // MARK: level == .everything (non-self actor)

    @Test func everythingFiresForIssueComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .issueComment(authorLogin: other, body: "hi"), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForCodeComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .codeComment(authorLogin: other, inReplyToAuthorLogin: nil, body: "lgtm", path: "a.swift", line: 10), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForReviewSubmitted() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .reviewSubmitted(authorLogin: other, state: .approved), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForCIFailure() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .ciFailure(runID: 7), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForStateChange() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .stateChange(newState: .merged, actorLogin: other), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForHeadPushed() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: ctx(), viewerLogin: me))
    }
    @Test func everythingFiresForOpened() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .opened(authorLogin: other), pr: ctx(), viewerLogin: me))
    }

    // MARK: level == .everything (self actor → filtered)

    @Test func everythingSkipsSelfComment() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .issueComment(authorLogin: me, body: "yo"), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func everythingSkipsSelfReview() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .reviewSubmitted(authorLogin: me, state: .approved), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func everythingSkipsSelfPush() {
        #expect(NotificationPolicy.shouldNotify(level: .everything, candidate: .headPushed(headSha: "abc", actorLogin: me), pr: ctx(), viewerLogin: me) == false)
    }

    // MARK: level == .personal, viewer authored PR

    @Test func personalMyPRFiresOnEveryKind() {
        let c = ctx(author: me)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(authorLogin: other, body: "hi"), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(authorLogin: other, inReplyToAuthorLogin: nil, body: "x", path: "p", line: 1), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .reviewSubmitted(authorLogin: other, state: .approved), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .stateChange(newState: .merged, actorLogin: other), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: c, viewerLogin: me))
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .opened(authorLogin: me), pr: c, viewerLogin: me) == false) // self
    }

    // MARK: level == .personal, viewer did NOT author

    @Test func personalCodeReplyToMeFires() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(authorLogin: other, inReplyToAuthorLogin: me, body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me))
    }
    @Test func personalCodeReplyToSomeoneElseDoesNotFire() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(authorLogin: other, inReplyToAuthorLogin: "rina", body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func personalCodeTopLevelDoesNotFire() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .codeComment(authorLogin: other, inReplyToAuthorLogin: nil, body: "?", path: "a", line: 5), pr: ctx(), viewerLogin: me) == false)
    }
    @Test func personalIssueCommentFiresIfViewerHasCommented() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(authorLogin: other, body: "x"), pr: ctx(viewerCommented: true), viewerLogin: me))
    }
    @Test func personalIssueCommentDoesNotFireIfViewerHasNotCommented() {
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .issueComment(authorLogin: other, body: "x"), pr: ctx(viewerCommented: false), viewerLogin: me) == false)
    }
    @Test func personalDoesNotFireOnOtherKindsForNonAuthor() {
        let c = ctx(viewerCommented: true)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .reviewSubmitted(authorLogin: other, state: .approved), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .ciFailure(runID: 1), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .stateChange(newState: .merged, actorLogin: other), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .headPushed(headSha: "abc", actorLogin: other), pr: c, viewerLogin: me) == false)
        #expect(NotificationPolicy.shouldNotify(level: .personal, candidate: .opened(authorLogin: other), pr: c, viewerLogin: me) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationPolicyTests 2>&1 | tail -20`
Expected: COMPILE ERROR — `NotificationPolicy` doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `PRTracker/Notifications/NotificationPolicy.swift`:

```swift
import Foundation

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

    private static func everythingAllows(_ k: NotificationCandidate.Kind) -> Bool {
        switch k {
        case .issueComment, .codeComment, .reviewSubmitted,
             .stateChange, .headPushed, .opened, .ciFailure:
            return true
        }
    }

    private static func personalAllows(_ k: NotificationCandidate.Kind,
                                       pr: PRContext,
                                       viewerLogin: String) -> Bool {
        if pr.authorLogin == viewerLogin { return everythingAllows(k) }
        switch k {
        case .codeComment(_, let inReplyToAuthor, _, _, _):
            return inReplyToAuthor == viewerLogin
        case .issueComment:
            return pr.viewerHasCommented
        default:
            return false
        }
    }

    private static func actorLogin(for k: NotificationCandidate.Kind) -> String? {
        switch k {
        case .issueComment(let a, _): return a
        case .codeComment(let a, _, _, _, _): return a
        case .reviewSubmitted(let a, _): return a
        case .stateChange(_, let a): return a
        case .headPushed(_, let a): return a
        case .opened(let a): return a
        case .ciFailure: return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationPolicyTests 2>&1 | tail -20`
Expected: PASS (all 17+ tests).

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Notifications/NotificationPolicy.swift PRTrackerTests/Notifications/NotificationPolicyTests.swift
git commit -m "feat(notifications): pure NotificationPolicy rule engine"
```

---

## Task 6 — `NotificationPoster`, `NotificationAuthorization`, `AppActivityProbing` + test fakes

**Files:**
- Create: `PRTracker/Notifications/NotificationPoster.swift`
- Create: `PRTracker/Notifications/NotificationAuthorization.swift`
- Create: `PRTracker/Notifications/AppActivityProbing.swift`
- Create: `PRTrackerTests/Notifications/Fakes.swift`

- [ ] **Step 1: Write `NotificationPoster.swift`**

```swift
import Foundation
import UserNotifications

protocol NotificationPoster {
    func post(_ content: UNNotificationContent) async
}

struct UNCenterPoster: NotificationPoster {
    func post(_ content: UNNotificationContent) async {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
```

- [ ] **Step 2: Write `NotificationAuthorization.swift`**

```swift
import Foundation
import UserNotifications

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

- [ ] **Step 3: Write `AppActivityProbing.swift`**

```swift
import Foundation
import AppKit

protocol AppActivityProbing: Sendable {
    @MainActor func isFrontmost() -> Bool
}

struct NSAppActivityProbe: AppActivityProbing {
    @MainActor func isFrontmost() -> Bool { NSApp.isActive }
}
```

- [ ] **Step 4: Write test fakes**

Create `PRTrackerTests/Notifications/Fakes.swift`:

```swift
import Foundation
import UserNotifications
@testable import PRTracker

final class CapturingPoster: NotificationPoster, @unchecked Sendable {
    var posted: [UNNotificationContent] = []
    func post(_ content: UNNotificationContent) async {
        posted.append(content)
    }
}

struct StubAuth: NotificationAuthorizing {
    let status: UNAuthorizationStatus
    func currentStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async -> UNAuthorizationStatus { status }
}

struct StubActivityProbe: AppActivityProbing {
    let frontmost: Bool
    @MainActor func isFrontmost() -> Bool { frontmost }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Notifications/NotificationPoster.swift PRTracker/Notifications/NotificationAuthorization.swift PRTracker/Notifications/AppActivityProbing.swift PRTrackerTests/Notifications/Fakes.swift
git commit -m "feat(notifications): poster, authorization, and activity protocols + test fakes"
```

---

## Task 7 — `NotificationDispatcher` skeleton + early-return tests

**Files:**
- Create: `PRTracker/Notifications/NotificationDispatcher.swift`
- Create: `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`

This task adds the dispatcher class with only the four early-return checks wired (level == .none / auth ≠ .authorized / app frontmost / no viewer login). Subsequent tasks add real candidate processing.

- [ ] **Step 1: Write failing tests**

Create `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct NotificationDispatcherTests {
    private func setup(level: NotificationLevel = .personal,
                       viewerLogin: String = "alex") throws -> (ModelContainer, Repo, ViewerState) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(repo)
        let viewer = User(login: viewerLogin)
        ctx.insert(viewer)
        let vs = ViewerState(viewer: viewer, activeRepoID: repo.id)
        vs.notificationLevel = level
        ctx.insert(vs)
        try ctx.save()
        return (container, repo, vs)
    }

    @Test func levelNoneShortCircuits() async throws {
        let (container, repo, _) = try setup(level: .none)
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func authDeniedShortCircuits() async throws {
        let (container, repo, _) = try setup()
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .denied),
                                                activity: StubActivityProbe(frontmost: false))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }

    @Test func appFrontmostShortCircuits() async throws {
        let (container, repo, _) = try setup()
        let poster = CapturingPoster()
        let dispatcher = NotificationDispatcher(modelContainer: container,
                                                poster: poster,
                                                auth: StubAuth(status: .authorized),
                                                activity: StubActivityProbe(frontmost: true))
        await dispatcher.process(repoID: repo.id)
        #expect(poster.posted.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — they fail to compile**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests 2>&1 | tail -20`
Expected: COMPILE ERROR — `NotificationDispatcher` doesn't exist.

- [ ] **Step 3: Implement the skeleton**

Create `PRTracker/Notifications/NotificationDispatcher.swift`:

```swift
import Foundation
import SwiftData
import UserNotifications

final class NotificationDispatcher {
    private let modelContainer: ModelContainer
    private let poster: NotificationPoster
    private let auth: NotificationAuthorizing
    private let activity: AppActivityProbing

    init(modelContainer: ModelContainer,
         poster: NotificationPoster,
         auth: NotificationAuthorizing = NotificationAuthorization(),
         activity: AppActivityProbing = NSAppActivityProbe()) {
        self.modelContainer = modelContainer
        self.poster = poster
        self.auth = auth
        self.activity = activity
    }

    func process(repoID: String) async {
        let ctx = ModelContext(modelContainer)
        guard let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first else { return }
        if vs.notificationLevel == .none { return }

        if await auth.currentStatus() != .authorized { return }
        if await MainActor.run(body: { activity.isFrontmost() }) { return }
        guard let viewerLogin = vs.viewer?.login else { return }

        _ = viewerLogin // suppress unused warning until Task 8 wires the real work
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Notifications/NotificationDispatcher.swift PRTrackerTests/Notifications/NotificationDispatcherTests.swift
git commit -m "feat(notifications): NotificationDispatcher skeleton + early-return gates"
```

---

## Task 8 — Dispatcher candidate collection + single-event posting

**Files:**
- Modify: `PRTracker/Notifications/NotificationDispatcher.swift`
- Modify: `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`

- [ ] **Step 1: Add a failing test for the single-comment case**

Append to `NotificationDispatcherTests` (inside the `@Suite struct`):

```swift
@Test func singleNewIssueCommentFires() async throws {
    let (container, repo, _) = try setup(level: .everything)
    let ctx = ModelContext(container)
    let author = User(login: "iris")
    ctx.insert(author)
    let pr = PullRequest(id: "PR_42", number: 42, title: "Add login",
                         state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                         openedAt: .now, updatedAt: .now,
                         author: author, repo: repo)
    ctx.insert(pr)
    let evt = TimelineEvent(id: "IC_1", type: .comment, at: .now,
                            pullRequest: pr, actor: author, body: "Looks good")
    ctx.insert(evt)
    try ctx.save()

    let poster = CapturingPoster()
    let dispatcher = NotificationDispatcher(modelContainer: container,
                                            poster: poster,
                                            auth: StubAuth(status: .authorized),
                                            activity: StubActivityProbe(frontmost: false))
    await dispatcher.process(repoID: repo.id)

    #expect(poster.posted.count == 1)
    #expect(poster.posted[0].title == "\(repo.id) #42")
    #expect(poster.posted[0].body.contains("iris"))
    #expect(poster.posted[0].body.contains("Looks good"))

    let logs = try ctx.fetch(FetchDescriptor<NotificationLog>())
    #expect(logs.count == 1)
    #expect(logs[0].id == "comment_IC_1")
}

@Test func idempotentReprocessing() async throws {
    let (container, repo, _) = try setup(level: .everything)
    let ctx = ModelContext(container)
    let author = User(login: "iris")
    ctx.insert(author)
    let pr = PullRequest(id: "PR_42", number: 42, title: "T",
                         state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                         openedAt: .now, updatedAt: .now, author: author, repo: repo)
    ctx.insert(pr)
    ctx.insert(TimelineEvent(id: "IC_1", type: .comment, at: .now,
                             pullRequest: pr, actor: author, body: "hi"))
    try ctx.save()

    let poster = CapturingPoster()
    let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                            auth: StubAuth(status: .authorized),
                                            activity: StubActivityProbe(frontmost: false))
    await dispatcher.process(repoID: repo.id)
    await dispatcher.process(repoID: repo.id)

    #expect(poster.posted.count == 1)
}

@Test func selfActionDoesNotFire() async throws {
    let (container, repo, _) = try setup(level: .everything)
    let ctx = ModelContext(container)
    let me = (try ctx.fetch(FetchDescriptor<ViewerState>())).first!.viewer!
    let pr = PullRequest(id: "PR_43", number: 43, title: "T",
                         state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                         openedAt: .now, updatedAt: .now, author: me, repo: repo)
    ctx.insert(pr)
    ctx.insert(TimelineEvent(id: "IC_X", type: .comment, at: .now,
                             pullRequest: pr, actor: me, body: "self"))
    try ctx.save()

    let poster = CapturingPoster()
    let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                            auth: StubAuth(status: .authorized),
                                            activity: StubActivityProbe(frontmost: false))
    await dispatcher.process(repoID: repo.id)
    #expect(poster.posted.isEmpty)
}
```

- [ ] **Step 2: Run tests — they fail**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests/singleNewIssueCommentFires 2>&1 | tail -20`
Expected: FAIL — no posts produced (skeleton is still empty).

- [ ] **Step 3: Implement candidate collection + content building + single-event posting**

Replace `process(repoID:)` and add helpers in `NotificationDispatcher.swift`:

```swift
func process(repoID: String) async {
    let ctx = ModelContext(modelContainer)
    guard let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first else { return }
    if vs.notificationLevel == .none { return }
    if await auth.currentStatus() != .authorized { return }
    if await MainActor.run(body: { activity.isFrontmost() }) { return }
    guard let viewerLogin = vs.viewer?.login else { return }

    let level = vs.notificationLevel
    let prs = (try? ctx.fetch(FetchDescriptor<PullRequest>(
        predicate: #Predicate { $0.repo.id == repoID }))) ?? []

    for pr in prs {
        let prCtx = PRContext(
            id: pr.id,
            authorLogin: pr.author.login,
            viewerHasCommented: viewerHasCommented(on: pr, viewerLogin: viewerLogin))
        let existing = Set(pr.notificationLogs.map(\.id))

        let candidates = collectCandidates(pr: pr, existing: existing)
        let filtered = candidates.filter { candidate in
            NotificationPolicy.shouldNotify(level: level,
                                            candidate: candidate.kind,
                                            pr: prCtx,
                                            viewerLogin: viewerLogin)
        }

        if filtered.isEmpty { continue }

        let content: UNNotificationContent =
            filtered.count == 1
            ? specificContent(filtered[0], pr: pr)
            : aggregateContent(count: filtered.count, pr: pr)

        await poster.post(content)

        for c in filtered {
            ctx.insert(NotificationLog(id: idFor(c),
                                       kind: kindFor(c),
                                       notifiedAt: .now,
                                       pullRequest: pr))
        }
    }

    try? ctx.save()
}

// MARK: - Candidate collection

private func viewerHasCommented(on pr: PullRequest, viewerLogin: String) -> Bool {
    if pr.timeline.contains(where: { $0.type == .comment && $0.actor?.login == viewerLogin }) { return true }
    if pr.reviewComments.contains(where: { $0.author.login == viewerLogin }) { return true }
    return false
}

private func collectCandidates(pr: PullRequest, existing: Set<String>) -> [NotificationCandidate] {
    var out: [NotificationCandidate] = []

    // Issue comments
    for event in pr.timeline where event.type == .comment {
        if existing.contains("comment_\(event.id)") { continue }
        let author = event.actor?.login ?? "unknown"
        out.append(NotificationCandidate(kind: .issueComment(authorLogin: author, body: event.body ?? ""), prID: pr.id))
    }

    // Code-review comments
    let byID = Dictionary(uniqueKeysWithValues: pr.reviewComments.map { ($0.id, $0) })
    for rc in pr.reviewComments {
        if existing.contains("comment_\(rc.id)") { continue }
        let inReplyToAuthor: String? = rc.inReplyToID.flatMap { byID[$0]?.author.login }
        out.append(NotificationCandidate(
            kind: .codeComment(authorLogin: rc.author.login,
                               inReplyToAuthorLogin: inReplyToAuthor,
                               body: rc.body, path: rc.path, line: rc.line),
            prID: pr.id))
    }

    // Reviews
    for event in pr.timeline where event.type == .review {
        if existing.contains("review_\(event.id)") { continue }
        let author = event.actor?.login ?? "unknown"
        let state = event.reviewState ?? .commented
        out.append(NotificationCandidate(kind: .reviewSubmitted(authorLogin: author, state: state), prID: pr.id))
    }

    // CI failures
    for run in pr.ciChecks where run.state == .fail {
        guard let runID = run.checkRunID else { continue }
        if existing.contains("ci_\(runID)") { continue }
        out.append(NotificationCandidate(kind: .ciFailure(runID: runID), prID: pr.id))
    }

    // State change
    let stateID = "state_\(pr.id)_\(pr.state.rawValue)"
    if !existing.contains(stateID),
       [PRState.merged, .closed, .open].contains(pr.state) {
        // Suppress the very first ".open" — opened is a separate trigger.
        // But ".open" after a prior non-open state IS a reopen — log set covers it.
        // We always include here; backfill seeds the initial state row.
        out.append(NotificationCandidate(kind: .stateChange(newState: pr.state, actorLogin: nil), prID: pr.id))
    }

    // Push
    let pushID = "push_\(pr.id)_\(pr.headSha)"
    if !existing.contains(pushID) {
        out.append(NotificationCandidate(kind: .headPushed(headSha: pr.headSha, actorLogin: nil), prID: pr.id))
    }

    // Opened
    if !existing.contains("opened_\(pr.id)") {
        out.append(NotificationCandidate(kind: .opened(authorLogin: pr.author.login), prID: pr.id))
    }

    return out
}

// MARK: - Content

private func specificContent(_ c: NotificationCandidate, pr: PullRequest) -> UNNotificationContent {
    let title = "\(pr.repo.id) #\(pr.number)"
    let m = UNMutableNotificationContent()
    m.title = title
    m.threadIdentifier = pr.id
    m.userInfo = ["prID": pr.id]
    m.sound = .default
    switch c.kind {
    case .issueComment(let author, let body):
        m.body = "\(author): \(body.prefix(200))"
    case .codeComment(let author, _, let body, let path, let line):
        let loc = line.map { "\(path):\($0)" } ?? path
        m.body = "\(author) commented on \(loc): \(body.prefix(200))"
    case .reviewSubmitted(let author, let state):
        let verb: String = {
            switch state {
            case .approved:         return "approved"
            case .changesRequested: return "requested changes on"
            case .commented:        return "reviewed"
            case .pending:          return "reviewed"
            }
        }()
        m.body = "\(author) \(verb) '\(pr.title)'"
    case .ciFailure:
        m.body = "CI failed on '\(pr.title)'"
    case .stateChange(let newState, let actor):
        let verb: String = {
            switch newState {
            case .merged: return "merged"
            case .closed: return "closed"
            case .open:   return "reopened"
            case .draft:  return "moved to draft"
            }
        }()
        m.body = "\(actor ?? "Someone") \(verb) '\(pr.title)'"
    case .headPushed(_, let actor):
        m.body = "\(actor ?? "Someone") pushed new commits to '\(pr.title)'"
    case .opened(let author):
        m.body = "\(author) opened '\(pr.title)'"
    }
    return m
}

private func aggregateContent(count: Int, pr: PullRequest) -> UNNotificationContent {
    let m = UNMutableNotificationContent()
    m.title = "\(pr.repo.id) #\(pr.number)"
    m.body = "\(count) updates on '\(pr.title)'"
    m.threadIdentifier = pr.id
    m.userInfo = ["prID": pr.id]
    m.sound = .default
    return m
}

private func idFor(_ c: NotificationCandidate) -> String {
    switch c.kind {
    case .issueComment, .codeComment:
        // c.prID is unused for the surrogate; the timeline/event id space is global.
        // Look up source ids via the candidate carrier — populated in collectCandidates.
        return logIDFromKind(c.kind, prID: c.prID)
    default:
        return logIDFromKind(c.kind, prID: c.prID)
    }
}

private func logIDFromKind(_ k: NotificationCandidate.Kind, prID: String) -> String {
    // We embedded source ids in the candidate authorship; rebuild deterministic id here.
    // For comment/code-comment/review we need the original event/comment id — which
    // we don't carry on the candidate. So we instead use the PR-scoped fallback for
    // those kinds. THIS IS WRONG — fix below by carrying ids on the candidate.
    fatalError("see Step 4 — candidate id carrier")
}

private func kindFor(_ c: NotificationCandidate) -> String {
    switch c.kind {
    case .issueComment, .codeComment: return "comment"
    case .reviewSubmitted: return "review"
    case .ciFailure: return "ci_failure"
    case .stateChange: return "state_change"
    case .headPushed: return "push"
    case .opened: return "opened"
    }
}
```

- [ ] **Step 4: Carry source ids on the candidate (fix the `idFor` gap)**

The candidate kind needs to carry the source surrogate so the dispatcher can build dedup ids without re-walking SwiftData. Update `PRTracker/Notifications/NotificationCandidate.swift`:

```swift
import Foundation

struct NotificationCandidate {
    enum Kind {
        case issueComment(eventID: String, authorLogin: String, body: String)
        case codeComment(commentID: String, authorLogin: String, inReplyToAuthorLogin: String?, body: String, path: String, line: Int?)
        case reviewSubmitted(eventID: String, authorLogin: String, state: ReviewState)
        case ciFailure(runID: Int)
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
    let viewerHasCommented: Bool
}
```

Update `NotificationPolicy.swift` to match the new associated values (only the destructuring in `actorLogin(for:)` and `personalAllows(_:pr:viewerLogin:)`):

```swift
private static func personalAllows(_ k: NotificationCandidate.Kind,
                                   pr: PRContext,
                                   viewerLogin: String) -> Bool {
    if pr.authorLogin == viewerLogin { return everythingAllows(k) }
    switch k {
    case .codeComment(_, _, let inReplyToAuthor, _, _, _):
        return inReplyToAuthor == viewerLogin
    case .issueComment:
        return pr.viewerHasCommented
    default:
        return false
    }
}

private static func actorLogin(for k: NotificationCandidate.Kind) -> String? {
    switch k {
    case .issueComment(_, let a, _): return a
    case .codeComment(_, let a, _, _, _, _): return a
    case .reviewSubmitted(_, let a, _): return a
    case .stateChange(_, let a): return a
    case .headPushed(_, let a): return a
    case .opened(let a): return a
    case .ciFailure: return nil
    }
}
```

Update the existing policy test cases similarly (every `.issueComment(...)`, `.codeComment(...)`, `.reviewSubmitted(...)` literal needs the new leading `eventID:`/`commentID:`). Use synthetic ids like `"e1"`, `"c1"` in tests.

Now replace `logIDFromKind` in `NotificationDispatcher.swift` with the real implementation:

```swift
private func logIDFromKind(_ k: NotificationCandidate.Kind, prID: String) -> String {
    switch k {
    case .issueComment(let eventID, _, _): return "comment_\(eventID)"
    case .codeComment(let commentID, _, _, _, _, _): return "comment_\(commentID)"
    case .reviewSubmitted(let eventID, _, _): return "review_\(eventID)"
    case .ciFailure(let runID): return "ci_\(runID)"
    case .stateChange(let newState, _): return "state_\(prID)_\(newState.rawValue)"
    case .headPushed(let sha, _): return "push_\(prID)_\(sha)"
    case .opened: return "opened_\(prID)"
    }
}
```

And update `collectCandidates(pr:existing:)` to pass the new fields:

```swift
for event in pr.timeline where event.type == .comment {
    if existing.contains("comment_\(event.id)") { continue }
    let author = event.actor?.login ?? "unknown"
    out.append(NotificationCandidate(kind: .issueComment(eventID: event.id, authorLogin: author, body: event.body ?? ""), prID: pr.id))
}

for rc in pr.reviewComments {
    if existing.contains("comment_\(rc.id)") { continue }
    let inReplyToAuthor: String? = rc.inReplyToID.flatMap { byID[$0]?.author.login }
    out.append(NotificationCandidate(
        kind: .codeComment(commentID: rc.id,
                           authorLogin: rc.author.login,
                           inReplyToAuthorLogin: inReplyToAuthor,
                           body: rc.body, path: rc.path, line: rc.line),
        prID: pr.id))
}

for event in pr.timeline where event.type == .review {
    if existing.contains("review_\(event.id)") { continue }
    let author = event.actor?.login ?? "unknown"
    let state = event.reviewState ?? .commented
    out.append(NotificationCandidate(kind: .reviewSubmitted(eventID: event.id, authorLogin: author, state: state), prID: pr.id))
}
```

Remove the temporary `fatalError` site; `idFor` becomes a thin shim:

```swift
private func idFor(_ c: NotificationCandidate) -> String {
    logIDFromKind(c.kind, prID: c.prID)
}
```

- [ ] **Step 5: Run all tests — verify pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: all tests pass — three new dispatcher tests + all 17+ policy tests.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Notifications/NotificationDispatcher.swift PRTracker/Notifications/NotificationCandidate.swift PRTracker/Notifications/NotificationPolicy.swift PRTrackerTests/Notifications/
git commit -m "feat(notifications): dispatcher candidate collection + single-event posting"
```

---

## Task 9 — Per-PR aggregation

**Files:**
- Modify: `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`

The aggregation behavior is already implemented in Task 8's `process(repoID:)` (the `filtered.count == 1 ? specific : aggregate` branch). This task adds a regression test confirming the bundle behavior.

- [ ] **Step 1: Add aggregation test**

Append to `NotificationDispatcherTests`:

```swift
@Test func multipleEventsOnOnePRAggregate() async throws {
    let (container, repo, _) = try setup(level: .everything)
    let ctx = ModelContext(container)
    let author = User(login: "iris")
    ctx.insert(author)
    let pr = PullRequest(id: "PR_50", number: 50, title: "Refactor sync",
                         state: .open, branchHead: "h", branchBase: "main", headSha: "abc",
                         openedAt: .now, updatedAt: .now, author: author, repo: repo)
    ctx.insert(pr)
    ctx.insert(TimelineEvent(id: "IC_1", type: .comment, at: .now, pullRequest: pr, actor: author, body: "one"))
    ctx.insert(TimelineEvent(id: "IC_2", type: .comment, at: .now, pullRequest: pr, actor: author, body: "two"))
    ctx.insert(CIRun(checkRunID: 999, name: "build", state: .fail, pr: pr))
    try ctx.save()

    let poster = CapturingPoster()
    let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                            auth: StubAuth(status: .authorized),
                                            activity: StubActivityProbe(frontmost: false))
    await dispatcher.process(repoID: repo.id)

    // 2 comments + CI failure + opened + push + state-change → at least 5 candidates collapsed into one banner.
    #expect(poster.posted.count == 1)
    #expect(poster.posted[0].body.contains("updates on 'Refactor sync'"))

    let logs = (try ctx.fetch(FetchDescriptor<NotificationLog>())).map(\.id)
    #expect(logs.contains("comment_IC_1"))
    #expect(logs.contains("comment_IC_2"))
    #expect(logs.contains("ci_999"))
    #expect(logs.contains("opened_PR_50"))
    #expect(logs.contains("push_PR_50_abc"))
    #expect(logs.contains("state_PR_50_open"))
}
```

- [ ] **Step 2: Run test — verify pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests/multipleEventsOnOnePRAggregate 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add PRTrackerTests/Notifications/NotificationDispatcherTests.swift
git commit -m "test(notifications): per-PR aggregation regression"
```

---

## Task 10 — `backfillSilentBaseline()` + test

**Files:**
- Modify: `PRTracker/Notifications/NotificationDispatcher.swift`
- Modify: `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`

- [ ] **Step 1: Add failing test**

Append:

```swift
@Test func backfillWritesLogRowsButPostsNothing() async throws {
    let (container, repo, _) = try setup(level: .personal)
    let ctx = ModelContext(container)
    let author = User(login: "iris")
    ctx.insert(author)
    let pr = PullRequest(id: "PR_60", number: 60, title: "X",
                         state: .open, branchHead: "h", branchBase: "main", headSha: "sha1",
                         openedAt: .now, updatedAt: .now, author: author, repo: repo)
    ctx.insert(pr)
    ctx.insert(TimelineEvent(id: "IC_A", type: .comment, at: .now, pullRequest: pr, actor: author, body: "a"))
    ctx.insert(CIRun(checkRunID: 111, name: "build", state: .fail, pr: pr))
    try ctx.save()

    let poster = CapturingPoster()
    let dispatcher = NotificationDispatcher(modelContainer: container, poster: poster,
                                            auth: StubAuth(status: .authorized),
                                            activity: StubActivityProbe(frontmost: false))
    await dispatcher.backfillSilentBaseline()

    #expect(poster.posted.isEmpty)
    let logs = (try ctx.fetch(FetchDescriptor<NotificationLog>())).map(\.id)
    #expect(logs.contains("comment_IC_A"))
    #expect(logs.contains("ci_111"))
    #expect(logs.contains("opened_PR_60"))
    #expect(logs.contains("push_PR_60_sha1"))
    #expect(logs.contains("state_PR_60_open"))

    // A subsequent process() must post nothing.
    await dispatcher.process(repoID: repo.id)
    #expect(poster.posted.isEmpty)
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests/backfillWritesLogRowsButPostsNothing 2>&1 | tail -20`
Expected: FAIL — `backfillSilentBaseline` doesn't exist.

- [ ] **Step 3: Implement `backfillSilentBaseline`**

Append to `NotificationDispatcher.swift`:

```swift
func backfillSilentBaseline() async {
    let ctx = ModelContext(modelContainer)
    let prs = (try? ctx.fetch(FetchDescriptor<PullRequest>())) ?? []
    for pr in prs {
        let existing = Set(pr.notificationLogs.map(\.id))
        for c in collectCandidates(pr: pr, existing: existing) {
            let id = idFor(c)
            ctx.insert(NotificationLog(id: id, kind: kindFor(c),
                                       notifiedAt: .now, pullRequest: pr))
        }
    }
    try? ctx.save()
}
```

- [ ] **Step 4: Run test — verify pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/NotificationDispatcherTests/backfillWritesLogRowsButPostsNothing 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Notifications/NotificationDispatcher.swift PRTrackerTests/Notifications/NotificationDispatcherTests.swift
git commit -m "feat(notifications): backfillSilentBaseline + dedup invariant test"
```

---

## Task 11 — `NotificationDelegate` (click routing + foreground gate)

**Files:**
- Create: `PRTracker/Notifications/NotificationDelegate.swift`

This file is wired into `PRTrackerApp` in Task 14. There's no good way to unit-test `UNUserNotificationCenterDelegate` without a real `UNNotificationResponse`, so the validation is the manual smoke pass in Task 17.

- [ ] **Step 1: Write the delegate**

```swift
import Foundation
import AppKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        if await MainActor.run(body: { NSApp.isActive }) { return [] }
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let prID = response.notification.request.content.userInfo["prID"] as? String else { return }
        await MainActor.run {
            appState?.selectedPRID = prID
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

(`AppState.selectedPRID` already exists; setting it surfaces the PR's detail pane via the existing `RootView` binding. No new field needed.)

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Notifications/NotificationDelegate.swift
git commit -m "feat(notifications): NotificationDelegate routes clicks to selectedPRID"
```

---

## Task 12 — `BadgeController` + tests

**Files:**
- Create: `PRTracker/Notifications/BadgeController.swift`
- Create: `PRTrackerTests/Notifications/BadgeControllerTests.swift`

For testability, the controller writes through a `DockBadgeSetting` protocol — production wires it to `NSApp.dockTile.badgeLabel`, tests use a fake.

- [ ] **Step 1: Write failing test**

Create `PRTrackerTests/Notifications/BadgeControllerTests.swift`:

```swift
import Testing
@testable import PRTracker

@Suite struct BadgeControllerTests {
    final class FakeDock: DockBadgeSetting, @unchecked Sendable {
        var label: String? = nil
        func setLabel(_ value: String?) { label = value }
    }

    @Test func emptyAttentionMeansNoDots() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 0
        c.apply()
        #expect(c.menuBarShowsDot == false)
        #expect(dock.label == nil)
    }

    @Test func bothEnabledWithAttentionShowsBoth() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        #expect(c.menuBarShowsDot == true)
        #expect(dock.label == "●")
    }

    @Test func togglingDockOffClearsLabel() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        c.dockEnabled = false
        c.apply()
        #expect(dock.label == nil)
        #expect(c.menuBarShowsDot == true)   // menu-bar unaffected
    }

    @Test func togglingMenuBarOffHidesDot() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.menuBarEnabled = false
        c.apply()
        #expect(c.menuBarShowsDot == false)
        #expect(dock.label == "●")          // dock unaffected
    }
}
```

- [ ] **Step 2: Run test — fails to compile**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/BadgeControllerTests 2>&1 | tail -20`
Expected: COMPILE ERROR — `BadgeController` doesn't exist.

- [ ] **Step 3: Implement `BadgeController`**

Create `PRTracker/Notifications/BadgeController.swift`:

```swift
import AppKit
import Foundation

protocol DockBadgeSetting: AnyObject {
    func setLabel(_ value: String?)
}

final class NSAppDockBadge: DockBadgeSetting {
    func setLabel(_ value: String?) {
        NSApp.dockTile.badgeLabel = value
    }
}

@Observable
final class BadgeController {
    var attentionCount: Int = 0
    var menuBarEnabled: Bool = true
    var dockEnabled: Bool = true

    @ObservationIgnored private let dock: DockBadgeSetting

    init(dock: DockBadgeSetting = NSAppDockBadge()) {
        self.dock = dock
    }

    var menuBarShowsDot: Bool { menuBarEnabled && attentionCount > 0 }
    var dockShowsBadge: Bool { dockEnabled && attentionCount > 0 }

    func apply() {
        dock.setLabel(dockShowsBadge ? "●" : nil)
    }
}
```

- [ ] **Step 4: Run test — verify pass**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/BadgeControllerTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Notifications/BadgeController.swift PRTrackerTests/Notifications/BadgeControllerTests.swift
git commit -m "feat(badging): BadgeController + DockBadgeSetting protocol"
```

---

## Task 13 — Menu-bar icon: corner-dot variant + `MenuBarBadge` rewrite

**Files:**
- Modify: `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift`
- Modify: `PRTracker/Views/MenuBar/MenuBarBadge.swift`
- Modify: `PRTracker/Views/MenuBar/MenuBarContentView.swift`
- Modify: `PRTracker/App/PRTrackerApp.swift`

- [ ] **Step 1: Rewrite the renderer for dot-only**

Replace the contents of `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift`:

```swift
import SwiftUI
import AppKit

enum MenuBarIconRenderer {
    static func image(showDot: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRs")!
        if !showDot { return base }
        let composite = NSImage(size: NSSize(width: 18, height: 18))
        composite.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        let dot = NSRect(x: 11, y: 11, width: 7, height: 7)
        NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: dot).fill()
        composite.unlockFocus()
        composite.isTemplate = false
        return composite
    }
}
```

- [ ] **Step 2: Replace `MenuBarBadge`**

Rewrite `PRTracker/Views/MenuBar/MenuBarBadge.swift`:

```swift
import SwiftUI

struct MenuBarLabel: View {
    let controller: BadgeController
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(showDot: controller.menuBarShowsDot))
    }
}
```

(The old `MenuBarBadge` class is gone; the menu-bar view reads the controller directly.)

- [ ] **Step 3: Update `MenuBarContentView` to drive `BadgeController.attentionCount`**

Open `PRTracker/Views/MenuBar/MenuBarContentView.swift`. Replace the `let badge: MenuBarBadge` property with `let controller: BadgeController`. Replace the `.task(id: prs.count) { badge.count = ... }` block with:

```swift
.task(id: prs.count) {
    controller.attentionCount = (buckets[.attention] ?? []).count
    controller.apply()
}
```

Update the call site signature so the constructor takes `controller:` rather than `badge:`.

- [ ] **Step 4: Update `PRTrackerApp` to construct + pass `BadgeController`**

In `PRTracker/App/PRTrackerApp.swift`:

```swift
let badge = MenuBarBadge()
```

becomes

```swift
let badgeController = BadgeController()
```

The `MenuBarExtra` content + label:

```swift
MenuBarExtra {
    MenuBarContentView(coordinator: coordinator, controller: badgeController)
        .environment(appState)
        .modelContainer(container)
} label: {
    MenuBarLabel(controller: badgeController)
}
```

- [ ] **Step 5: Build + run all tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/MenuBar/ PRTracker/App/PRTrackerApp.swift
git commit -m "feat(badging): menu-bar corner-dot variant + BadgeController wiring"
```

---

## Task 14 — Wire `NotificationDispatcher` + `NotificationDelegate` into the app

**Files:**
- Modify: `PRTracker/App/PRTrackerApp.swift`
- Modify: `PRTracker/Sync/SyncCoordinator.swift`

- [ ] **Step 1: Add a dispatcher hook to `SyncCoordinator`**

In `PRTracker/Sync/SyncCoordinator.swift`, add a stored property + setter and call it after a successful sync.

Add near the top of the class:

```swift
var notificationDispatcher: NotificationDispatcher?
var badgeController: BadgeController?
```

In `refresh()`, replace the line `lastSyncAt = .now` with:

```swift
lastSyncAt = .now
if let d = notificationDispatcher { await d.process(repoID: repoID) }
```

- [ ] **Step 2: Wire it from `PRTrackerApp`**

In `PRTracker/App/PRTrackerApp.swift`, after constructing `coordinator`, build the dispatcher + delegate and attach them. Inside `init()`:

```swift
let dispatcher = NotificationDispatcher(modelContainer: c, poster: UNCenterPoster())
let delegate = NotificationDelegate()
delegate.appState = self.appState
UNUserNotificationCenter.current().delegate = delegate

self.notificationDelegate = delegate
self.dispatcher = dispatcher
self.coordinator.notificationDispatcher = dispatcher
self.coordinator.badgeController = badgeController
```

Declare two new stored properties on `PRTrackerApp` to retain the delegate + dispatcher (delegate is `weak`-referenced by `UNUserNotificationCenter`, so the app must keep it alive):

```swift
let notificationDelegate: NotificationDelegate
let dispatcher: NotificationDispatcher
```

- [ ] **Step 3: Build + tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/App/PRTrackerApp.swift PRTracker/Sync/SyncCoordinator.swift
git commit -m "feat(notifications): wire dispatcher + delegate at app init"
```

---

## Task 15 — Settings: Notifications tab

**Files:**
- Modify: `PRTracker/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add the tab + its handlers**

Add a new property + the tab to `SettingsView`:

```swift
@State private var authDeniedHintVisible: Bool = false
```

In `body`, add the tab between General and Account:

```swift
TabView {
    generalTab.tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
    notificationsTab.tabItem { SwiftUI.Label("Notifications", systemImage: "bell") }
    accountTab.tabItem { SwiftUI.Label("Account", systemImage: "person.circle") }
    repoTab.tabItem    { SwiftUI.Label("Repository", systemImage: "folder") }
}
```

Add the tab body:

```swift
@ViewBuilder private var notificationsTab: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("Notify me about").font(.headline)
        Picker("", selection: Binding(
            get: { vs.notificationLevel },
            set: { newValue in
                let previous = vs.notificationLevel
                vs.notificationLevel = newValue
                try? ctx.save()
                Task { await handleLevelChange(previous: previous, newValue: newValue) }
            })) {
            Text("Everything — all comments, reviews, CI failures, commits, and state changes").tag(NotificationLevel.everything)
            Text("Personal — PRs you authored, replies to your comments").tag(NotificationLevel.personal)
            Text("None — no notifications").tag(NotificationLevel.none)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()

        if authDeniedHintVisible {
            Text("macOS notifications are disabled for PR Tracker. Enable in System Settings → Notifications → PR Tracker.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.textFaint)
        }

        Divider().padding(.vertical, 4)

        Text("Badging").font(.headline)
        Toggle("Show indicator on menu-bar icon", isOn: Binding(
            get: { vs.menuBarBadgeEnabled },
            set: { newValue in
                vs.menuBarBadgeEnabled = newValue
                try? ctx.save()
                coordinator.badgeController?.menuBarEnabled = newValue
                coordinator.badgeController?.apply()
            }))
        Toggle("Show indicator on Dock icon", isOn: Binding(
            get: { vs.dockBadgeEnabled },
            set: { newValue in
                vs.dockBadgeEnabled = newValue
                try? ctx.save()
                coordinator.badgeController?.dockEnabled = newValue
                coordinator.badgeController?.apply()
            }))

        Spacer()
    }
    .task { await refreshAuthHint() }
}

private func handleLevelChange(previous: NotificationLevel, newValue: NotificationLevel) async {
    if newValue == .none {
        authDeniedHintVisible = false
        return
    }
    let auth = NotificationAuthorization()
    var status = await auth.currentStatus()
    if status == .notDetermined {
        status = await auth.requestAuthorization()
    }
    if status == .authorized && previous == .none {
        await coordinator.notificationDispatcher?.backfillSilentBaseline()
    }
    authDeniedHintVisible = (status == .denied)
}

private func refreshAuthHint() async {
    let status = await NotificationAuthorization().currentStatus()
    authDeniedHintVisible = (vs.notificationLevel != .none && status == .denied)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build 2>&1 | tail -15`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Views/Settings/SettingsView.swift
git commit -m "feat(notifications): Settings Notifications tab + level/badge handlers"
```

---

## Task 16 — First-launch auth flow in `RootView`

**Files:**
- Modify: `PRTracker/App/RootView.swift`

- [ ] **Step 1: Add the first-launch helper**

In `RootView`, inject the dispatcher via the coordinator (already accessible through `coordinator.notificationDispatcher`). Add a `@State` flag and a `.task` that runs once:

Replace the existing `body`'s `.task { coordinator.start() }` for the `signedIn` branch with:

```swift
MainView(coordinator: coordinator, onOpenSettings: { openSettings() })
    .task {
        coordinator.start()
        await firstLaunchAuthorizationIfNeeded()
    }
```

Add the helper:

```swift
@State private var didRunFirstLaunchAuth: Bool = false

private func firstLaunchAuthorizationIfNeeded() async {
    if didRunFirstLaunchAuth { return }
    didRunFirstLaunchAuth = true

    guard let vs = viewerStates.first else { return }
    if vs.notificationLevel == .none { return }

    let auth = NotificationAuthorization()
    var status = await auth.currentStatus()
    if status == .notDetermined {
        status = await auth.requestAuthorization()
    }
    guard status == .authorized else { return }

    // Empty-log guard so this is idempotent across launches AND covers the
    // "previously denied, now allowed" path.
    let logCount = (try? ctx.fetch(FetchDescriptor<NotificationLog>()))?.count ?? 0
    if logCount == 0 {
        await coordinator.notificationDispatcher?.backfillSilentBaseline()
    }
}
```

- [ ] **Step 2: Build + tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/App/RootView.swift
git commit -m "feat(notifications): first-launch authorization + baseline backfill"
```

---

## Task 17 — Manual smoke pass + final commit

**Files:** None (validation only).

The following walks the user-facing behaviors that can't be unit-tested (real `UNUserNotificationCenter`, dock badge, menu-bar render).

- [ ] **Step 1: Build a release build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Launch + grant authorization**

Open the built `.app`. On first launch, expect the macOS permission prompt. Click Allow.

- [ ] **Step 3: Trigger a real PR event**

Comment on a PR in the configured repository (from another GitHub account so `actor != viewer`). Wait for the next sync.

**Verify:** A banner appears with `<repo> #<n>` title and `<author>: <body excerpt>` body. The detail pane is NOT open in the app at this moment (app is in background).

- [ ] **Step 4: Click the banner**

Banner → click. App becomes active; detail pane shows the PR.

- [ ] **Step 5: App-frontmost suppression**

Keep the app frontmost. Have someone post another comment. Next sync should produce no banner. Switch to another app; next sync should banner the now-eligible event.

- [ ] **Step 6: Switch levels**

Open Settings → Notifications. Set level to **None**. Trigger another comment → no banner. Set back to **Personal** → next sync banners if conditions met.

- [ ] **Step 7: Toggle badges**

In Settings → Notifications, with attention count > 0, toggle menu-bar icon off (dot disappears). Toggle Dock icon off (Dock dot disappears). Toggle back on (both restored).

- [ ] **Step 8: Revoke authorization externally**

System Settings → Notifications → PR Tracker → set to "None". Return to PR Tracker → open Notifications tab. The denied hint text should appear under the picker.

- [ ] **Step 9: Final commit if anything was tweaked**

If any manual-test discovery required a tweak, commit it with `fix(notifications): <change>`. Otherwise nothing to do.

---

## Self-Review

I read this plan against the spec section-by-section. Coverage check:

- §2.1 (Everything event surface) — Task 5 + Task 8 (`collectCandidates` + policy).
- §2.2 (Personal eligibility) — Task 5 policy tests.
- §2.3 (no self-notify) — `personalAllows` short-circuit + dedicated test (`selfActionDoesNotFire`, `everythingSkipsSelf*`).
- §3 (aggregation) — Task 8 implementation; Task 9 regression test.
- §4 (frontmost suppression) — Task 7 (`appFrontmostShortCircuits`).
- §5 (architecture / file list) — Task 1–14 cover every new + modified file in §5.1/§5.2.
- §6 (data model) — Tasks 1, 2.
- §7 (NotificationPolicy) — Task 5.
- §8 (NotificationDispatcher) — Tasks 7, 8, 9, 10.
- §9 (NotificationPoster) — Task 6.
- §10 (NotificationDelegate + deep-link) — Task 11. (Note: I simplified the spec's `pendingDeepLink` to use existing `selectedPRID`; deep-link semantics still match.)
- §11 (Authorization + first-launch) — Tasks 6 + 16.
- §12 (BadgeController) — Tasks 12, 13.
- §13 (Settings UI) — Task 15.
- §14 (sandbox/entitlements) — no work needed.
- §15 (Testing) — Tasks 5, 7, 8, 9, 10, 12, 17.

**Placeholder scan:** No "TBD"/"TODO"/"handle edge cases" left. Step 4 of Task 8 includes a deliberate `fatalError` placeholder followed by the real implementation in the same step — flagged as intentional refactor mid-step, not an unfinished plan element.

**Type consistency:** `NotificationCandidate.Kind` is changed in Task 8 Step 4 (adding `eventID:` / `commentID:` to comment/review variants); the policy code and existing policy tests are updated in the same step. Dispatcher uses the same kind names everywhere. `BadgeController` properties (`attentionCount`, `menuBarEnabled`, `dockEnabled`, `menuBarShowsDot`, `dockShowsBadge`, `apply()`) consistent across Tasks 12, 13, 14, 15. `NotificationDispatcher` init params (`modelContainer`, `poster`, `auth`, `activity`) consistent across Tasks 7, 8, 14.

**Spec deviation worth flagging:** §10 of the spec discusses an `AppState.pendingDeepLink` field with a toast for "PR aged out of feed." I dropped that in favor of using the existing `AppState.selectedPRID` (Task 11) because `RootView` already routes to detail when `selectedPRID` is non-nil and present in `prs`. The toast for missing PRs is deferred — falling through gracefully (detail simply doesn't appear; user sees the empty detail view) is acceptable for v1. If the user wants the toast, it can be a quick follow-up.
