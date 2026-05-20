# Mail-style Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current three-pane Sidebar + Feed + drilled-detail layout with a two-pane mail-style layout — fixed 380pt source list (repo selector + filter pills + scrollable PR rows + account footer) with a permanent detail pane on the right. Restyle Onboarding, Settings, and the MenuBarExtra to the same token palette.

**Architecture:** SwiftUI on macOS 26 with SwiftData persistence. Layout uses a `HStack(spacing: 0)` with a fixed-width source column (no user-resizable split). Read state is derived from a new `PullRequest.lastReadAt: Date?` field. All filter mapping reuses the existing `Classifier` logic, exposed through a new `MailFilter` enum. Theme is system-driven by default but overridable via a Settings picker stored on `ViewerState`.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`), AppKit interop for dynamic colors (already used in `Tokens.swift`).

**Spec reference:** `docs/superpowers/specs/2026-05-19-mail-redesign-design.md`
**Branch:** `redesign` (already created and current)

---

## File Structure

### Create

- `PRTracker/Views/Mail/MailFilter.swift` — new enum + label/dot mapping
- `PRTracker/Views/Mail/MailSourceColumn.swift` — left column container
- `PRTracker/Views/Mail/RepoSelectorCard.swift` — top card
- `PRTracker/Views/Mail/FilterPillBar.swift` — sticky pill strip
- `PRTracker/Views/Mail/MailListView.swift` — owns FilterPillBar + scrollable rows
- `PRTracker/Views/Mail/MailRowView.swift` — single row
- `PRTracker/Views/Mail/UnreadDot.swift` — small reusable view
- `PRTracker/Views/Mail/MiniGaugeDots.swift` — small reusable view
- `PRTracker/Views/Mail/AccountFooter.swift` — viewer chip
- `PRTracker/Views/Mail/MailDetailHeader.swift` — new header (replaces PRDetailView's)
- `PRTracker/Views/Mail/MailEmptyDetailView.swift` — empty-state pane
- `PRTracker/Views/Mail/SelectionReconcile.swift` — pure-function helper
- `PRTrackerTests/Mail/MailFilterTests.swift`
- `PRTrackerTests/Mail/PullRequestReadStateTests.swift`
- `PRTrackerTests/Mail/SelectionReconcileTests.swift`

### Modify

- `PRTracker/DesignSystem/Tokens.swift` — add missing keys (approvedBg, changesBg, pendingBg, commentedBg, accentText, rowHover, rowSelect)
- `PRTracker/Models/PullRequest.swift` — add `lastReadAt: Date?`, update `isUnread`
- `PRTracker/Models/ViewerState.swift` — add `themePreferenceRaw: String`
- `PRTracker/Sync/SyncActor.swift` — add `setLastReadAt(prID:date:)`
- `PRTracker/App/AppState.swift` — drop `activeSection`, add `activeFilter`
- `PRTracker/App/RootView.swift` — rewrite `MainView` body to two-pane composition
- `PRTracker/Views/Detail/PRDetailView.swift` — strip the back button, fold in MailDetailHeader
- `PRTracker/Views/Detail/DetailRightRail.swift` — reorder sections; replace Mark all seen/unseen with a single "Mark as unread"
- `PRTracker/Views/Detail/TimelineColumn.swift` — fidelity pass (rail position, cutout, accent ring on new)
- `PRTracker/Views/Detail/TimelineEventRow.swift` — 0.48 seen opacity, 4pt accent bar on new
- `PRTracker/Views/Settings/SettingsView.swift` — add theme picker; token/typography pass
- `PRTracker/Views/Onboarding/OnboardingView.swift` — token/typography pass
- `PRTracker/Views/MenuBar/MenuBarContentView.swift` — compressed mail-row style
- `PRTrackerTests/Sync/SyncActorTests.swift` — add a `setLastReadAt` test

### Delete (in the final cleanup task)

- `PRTracker/Views/Feed/Sidebar.swift`
- `PRTracker/Views/Feed/FeedView.swift`
- `PRTracker/Views/Feed/FeedSection.swift`
- `PRTracker/Views/Feed/FeedToolbar.swift`
- `PRTracker/Views/Feed/PRCardView.swift`
- `PRTracker/Views/Feed/StatusGauge.swift`

---

## Task 1: Extend Tokens with missing palette keys

**Files:**
- Modify: `PRTracker/DesignSystem/Tokens.swift`

The existing `Tokens.swift` already defines most keys with `NSColor.dynamic(light:dark:)` providers. Add the keys the mail design adds.

- [ ] **Step 1: Add the new keys**

Open `PRTracker/DesignSystem/Tokens.swift`. Inside `enum Tokens`, after the existing `newHighlight` line, append:

```swift
    // MARK: - Mail-redesign additions

    static let approvedBg   = Color(nsColor: .dynamic(light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 0.10),
                                                       dark:  NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 0.15)))
    static let changesBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 0.10),
                                                       dark:  NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 0.15)))
    static let pendingBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.60, green: 0.40, blue: 0.00, alpha: 0.10),
                                                       dark:  NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 0.15)))
    static let commentedBg  = Color(nsColor: .dynamic(light: NSColor(red: 0.43, green: 0.47, blue: 0.51, alpha: 0.10),
                                                       dark:  NSColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.15)))
    static let accentText   = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.38, blue: 0.80, alpha: 1),
                                                       dark:  NSColor(red: 0.39, green: 0.66, blue: 1.00, alpha: 1)))
    static let rowHover     = Color(nsColor: .dynamic(light: NSColor(white: 0, alpha: 0.03),
                                                       dark:  NSColor(white: 1, alpha: 0.04)))
    static let rowSelect    = Color(nsColor: .dynamic(light: NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 0.10),
                                                       dark:  NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 0.20)))
```

- [ ] **Step 2: Verify the project still builds**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PRTracker/DesignSystem/Tokens.swift
git commit -m "feat(tokens): add mail-redesign palette keys (bg tints, accentText, row states)"
```

---

## Task 2: Add `PullRequest.lastReadAt` and update `isUnread`

**Files:**
- Modify: `PRTracker/Models/PullRequest.swift`
- Create: `PRTrackerTests/Mail/PullRequestReadStateTests.swift`

This drops a constraint: the current `isUnread = timeline.contains { !$0.isSeen }` rule returns false for PRs with empty timelines (lazy-fetched), which makes them appear read before they've ever been opened. New rule: PR is unread if `lastReadAt == nil` OR `updatedAt > lastReadAt`.

- [ ] **Step 1: Write the failing tests**

Create `PRTrackerTests/Mail/PullRequestReadStateTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct PullRequestReadStateTests {
    private func makePR(updatedAt: Date, lastReadAt: Date?) throws -> PullRequest {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let user = User(login: "alex", id: 1, name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(user); ctx.insert(repo)
        let pr = PullRequest(id: "PR_1", number: 1, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: updatedAt, updatedAt: updatedAt,
                             author: user, repo: repo)
        pr.lastReadAt = lastReadAt
        ctx.insert(pr)
        try ctx.save()
        return pr
    }

    @Test func unreadWhenNeverRead() throws {
        let pr = try makePR(updatedAt: Date(timeIntervalSince1970: 1000), lastReadAt: nil)
        #expect(pr.isUnread == true)
    }

    @Test func readWhenLastReadAtEqualsUpdatedAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t, lastReadAt: t)
        #expect(pr.isUnread == false)
    }

    @Test func readWhenLastReadAtAfterUpdatedAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t, lastReadAt: t.addingTimeInterval(60))
        #expect(pr.isUnread == false)
    }

    @Test func unreadWhenUpdatedAtAfterLastReadAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t.addingTimeInterval(60), lastReadAt: t)
        #expect(pr.isUnread == true)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail to compile**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAIL|cannot find" | head -10
```
Expected: errors about `lastReadAt` being an unknown property on `PullRequest`.

- [ ] **Step 3: Add the `lastReadAt` field and update `isUnread`**

Edit `PRTracker/Models/PullRequest.swift`. Add a `var lastReadAt: Date?` after the existing `var involvedHint: String?` line:

```swift
    var attentionHint: String?
    var mentionHint: String?
    var involvedHint: String?
    var lastReadAt: Date?
```

Then replace the existing `isUnread` computed property:

```swift
    /// A PR is unread iff it's never been read, or its `updatedAt` is newer than the last read time.
    var isUnread: Bool {
        guard let lastReadAt else { return true }
        return updatedAt > lastReadAt
    }
```

No `init` change is required — `lastReadAt` defaults to `nil` for existing rows (SwiftData additive migration).

- [ ] **Step 4: Run the tests and verify they pass**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/PullRequestReadStateTests 2>&1 | tail -20
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Models/PullRequest.swift PRTrackerTests/Mail/PullRequestReadStateTests.swift
git commit -m "feat(model): add PullRequest.lastReadAt, derive isUnread from it"
```

---

## Task 3: Add `SyncActor.setLastReadAt(prID:date:)`

**Files:**
- Modify: `PRTracker/Sync/SyncActor.swift`
- Modify: `PRTrackerTests/Sync/SyncActorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PRTrackerTests/Sync/SyncActorTests.swift` (before the closing `}` of the `@Suite`):

```swift
    @Test func setLastReadAtUpdatesPullRequest() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await actor.setLastReadAt(prID: "PR_5107", date: t)
        let ctx = ModelContext(container)
        let pr = try ctx.fetch(FetchDescriptor<PullRequest>()).first
        #expect(pr?.lastReadAt == t)
    }

    @Test func setLastReadAtClearsWhenNil() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        try await actor.setLastReadAt(prID: "PR_5107", date: Date())
        try await actor.setLastReadAt(prID: "PR_5107", date: nil)
        let ctx = ModelContext(container)
        let pr = try ctx.fetch(FetchDescriptor<PullRequest>()).first
        #expect(pr?.lastReadAt == nil)
    }
```

- [ ] **Step 2: Verify the tests fail to compile**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep "setLastReadAt" | head -5
```
Expected: `cannot find 'setLastReadAt'` error.

- [ ] **Step 3: Implement `setLastReadAt`**

Open `PRTracker/Sync/SyncActor.swift`. After the `setSeenUpTo` method (around line 223), before the closing `}` of the actor, add:

```swift
    func setLastReadAt(prID: String, date: Date?) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        pr.lastReadAt = date
        try ctx.save()
    }
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SyncActorTests 2>&1 | tail -10
```
Expected: All `SyncActorTests` pass (including the two new ones).

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Sync/SyncActor.swift PRTrackerTests/Sync/SyncActorTests.swift
git commit -m "feat(sync): add SyncActor.setLastReadAt(prID:date:)"
```

---

## Task 4: Add `MailFilter` enum + bucket helper

**Files:**
- Create: `PRTracker/Views/Mail/MailFilter.swift`
- Create: `PRTrackerTests/Mail/MailFilterTests.swift`

The seven filters used by the source list: `All, Attention, Review, Mentions, Mine, Involved, Merged` (where `Merged` ⇄ `.recent`). The mapping reuses the existing `Classifier.section(...)` 1:1.

- [ ] **Step 1: Write the failing tests**

Create `PRTrackerTests/Mail/MailFilterTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct MailFilterTests {
    @Test func allCasesInOrder() {
        #expect(MailFilter.allCases == [.all, .attention, .review, .mentions, .mine, .involved, .recent])
    }

    @Test func displayLabels() {
        #expect(MailFilter.all.label       == "All")
        #expect(MailFilter.attention.label == "Attention")
        #expect(MailFilter.review.label    == "Review")
        #expect(MailFilter.mentions.label  == "Mentions")
        #expect(MailFilter.mine.label      == "Mine")
        #expect(MailFilter.involved.label  == "Involved")
        #expect(MailFilter.recent.label    == "Merged")
    }

    @Test func sectionMappingMatchesFilter() {
        // Each non-.all filter corresponds to exactly the Section with the same raw value.
        #expect(MailFilter.attention.section == .attention)
        #expect(MailFilter.review.section    == .review)
        #expect(MailFilter.mentions.section  == .mentions)
        #expect(MailFilter.mine.section      == .mine)
        #expect(MailFilter.involved.section  == .involved)
        #expect(MailFilter.recent.section    == .recent)
        #expect(MailFilter.all.section       == nil)
    }
}
```

- [ ] **Step 2: Verify it fails to compile**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "cannot find 'MailFilter'" | head -3
```
Expected: errors about `MailFilter`.

- [ ] **Step 3: Create `MailFilter.swift`**

Create `PRTracker/Views/Mail/MailFilter.swift`:

```swift
import Foundation
import SwiftUI

/// Filter pills shown across the top of the source list. `All` aggregates everything;
/// every other case corresponds 1:1 to a `Section` produced by `Classifier`.
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case all, attention, review, mentions, mine, involved, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       "All"
        case .attention: "Attention"
        case .review:    "Review"
        case .mentions:  "Mentions"
        case .mine:      "Mine"
        case .involved:  "Involved"
        case .recent:    "Merged"
        }
    }

    /// The `Section` this filter selects, or `nil` for `.all`.
    var section: Section? {
        switch self {
        case .all:       nil
        case .attention: .attention
        case .review:    .review
        case .mentions:  .mentions
        case .mine:      .mine
        case .involved:  .involved
        case .recent:    .recent
        }
    }

    /// Dot color rendered on the pill (and on the row's priority rail).
    /// Hidden on `.all`.
    var dotColor: Color? {
        section?.lane.color
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/MailFilterTests 2>&1 | tail -10
```
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Mail/MailFilter.swift PRTrackerTests/Mail/MailFilterTests.swift
git commit -m "feat(mail): MailFilter enum mapping to existing Section/Lane"
```

---

## Task 5: Selection-reconcile helper + tests

**Files:**
- Create: `PRTracker/Views/Mail/SelectionReconcile.swift`
- Create: `PRTrackerTests/Mail/SelectionReconcileTests.swift`

Pure function: given the previously selected PR ID and the newly filtered list (in display order), return the ID that should now be selected.

- [ ] **Step 1: Write the failing tests**

Create `PRTrackerTests/Mail/SelectionReconcileTests.swift`:

```swift
import Testing
@testable import PRTracker

@Suite struct SelectionReconcileTests {
    @Test func keepsExistingWhenStillInList() {
        let result = SelectionReconcile.next(previous: "B", in: ["A", "B", "C"])
        #expect(result == "B")
    }

    @Test func selectsFirstWhenPreviousIsGone() {
        let result = SelectionReconcile.next(previous: "X", in: ["A", "B", "C"])
        #expect(result == "A")
    }

    @Test func selectsFirstWhenPreviousWasNil() {
        let result = SelectionReconcile.next(previous: nil, in: ["A", "B", "C"])
        #expect(result == "A")
    }

    @Test func returnsNilWhenListEmpty() {
        let result = SelectionReconcile.next(previous: "B", in: [])
        #expect(result == nil)
    }

    @Test func returnsNilWhenListEmptyAndPreviousNil() {
        let result = SelectionReconcile.next(previous: nil, in: [])
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Verify they fail to compile**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep "SelectionReconcile" | head -3
```
Expected: `cannot find 'SelectionReconcile'`.

- [ ] **Step 3: Create the helper**

Create `PRTracker/Views/Mail/SelectionReconcile.swift`:

```swift
import Foundation

/// Pure helper for reconciling list selection across filter changes.
///
/// The rule: keep the previous selection if it's still in the new list,
/// otherwise pick the first item, otherwise `nil` (empty list).
enum SelectionReconcile {
    static func next(previous: String?, in newList: [String]) -> String? {
        if let previous, newList.contains(previous) { return previous }
        return newList.first
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/SelectionReconcileTests 2>&1 | tail -10
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Mail/SelectionReconcile.swift PRTrackerTests/Mail/SelectionReconcileTests.swift
git commit -m "feat(mail): pure SelectionReconcile.next helper + tests"
```

---

## Task 6: Update `AppState` — drop `activeSection`, add `activeFilter`

**Files:**
- Modify: `PRTracker/App/AppState.swift`

The whole file is rewritten — small enough to show verbatim.

- [ ] **Step 1: Replace the file contents**

Open `PRTracker/App/AppState.swift` and replace its contents with:

```swift
import Foundation
import SwiftData

@Observable
final class AppState {
    var activeFilter: MailFilter = .all
    var selectedPRID: String? = nil
    var rateLimitRemaining: Int? = nil
    var rateLimitResetAt: Date? = nil
}
```

(`activeSection` is removed; consumers — Sidebar, FeedView, RootView — are still using it but those views are about to be replaced. We accept a brief compile break here and resolve in the next two tasks.)

- [ ] **Step 2: Verify the project does NOT build yet (expected)**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | grep "activeSection" | head -3
```
Expected: errors referencing `activeSection` in `Sidebar.swift`, `FeedView.swift`, `RootView.swift`.

That's OK — Task 7 introduces the new MainView body and Task 16 removes the obsolete files.

- [ ] **Step 3: Commit (broken)**

This commit alone leaves the tree non-building. That's an explicit, documented step toward the cutover in Task 7. If you prefer to keep every commit green, defer this commit and stage it together with Task 7's diff.

```bash
git add PRTracker/App/AppState.swift
git commit -m "refactor(state): replace AppState.activeSection with activeFilter"
```

---

## Task 7: Replace `MainView` body with two-pane composition (placeholder source list)

**Files:**
- Modify: `PRTracker/App/RootView.swift`
- Create: `PRTracker/Views/Mail/MailSourceColumn.swift` (placeholder)

Cut the `NavigationSplitView`. Drop in an `HStack(spacing: 0)` with a fixed-width `MailSourceColumn` on the leading edge and the existing `PRDetailView` or empty placeholder on the trailing edge. Filter changes select the first row in the new list. The detail-slide-in transition is dropped; the detail pane is permanent.

This task introduces the new shell without yet replacing the source list internals. The placeholder `MailSourceColumn` just renders a `List` of PR titles so the app is interactive and we can verify selection.

- [ ] **Step 1: Create a placeholder `MailSourceColumn`**

Create `PRTracker/Views/Mail/MailSourceColumn.swift`:

```swift
import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]

    var onOpenSettings: () -> Void

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            // TODO(Task 8): replace with RepoSelectorCard
            Text("Repo Selector").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)

            // TODO(Task 10): replace with MailListView (filter pills + rows)
            List(selection: $appState.selectedPRID) {
                ForEach(prs) { pr in
                    Text("#\(pr.number) — \(pr.title)").lineLimit(1).tag(pr.id)
                }
            }
            .listStyle(.plain)

            // TODO(Task 11): replace with AccountFooter
            Divider()
            HStack { Text("Account").font(.system(size: 11)); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
```

- [ ] **Step 2: Rewrite `MainView`'s body**

Open `PRTracker/App/RootView.swift`. Replace the `MainView` struct entirely (everything from `struct MainView: View {` through its closing `}` plus the trailing `private func counts(...)` helper, which is no longer needed) with:

```swift
struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]
    @Query private var prs: [PullRequest]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)

        HStack(spacing: 0) {
            MailSourceColumn(onOpenSettings: onOpenSettings)

            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, syncActor: coordinator.syncActorForView)
            } else {
                MailEmptyDetailViewPlaceholder()
            }
        }
        .navigationTitle(repo?.id ?? "")
    }
}

/// Temporary placeholder until Task 13 introduces the real empty view.
private struct MailEmptyDetailViewPlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Text("No pull request selected.")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textFaint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.contentBg)
    }
}
```

- [ ] **Step 3: Verify the project builds**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify the shell**

Run the app. Confirm:
- The window opens with a 380pt sidebar on the left and content area on the right.
- Selecting a row in the placeholder list opens that PR's detail on the right.
- Clearing selection (clicking empty space) returns to "No pull request selected."

- [ ] **Step 5: Commit**

```bash
git add PRTracker/App/RootView.swift PRTracker/Views/Mail/MailSourceColumn.swift
git commit -m "feat(mail): two-pane shell with placeholder source list"
```

---

## Task 8: `UnreadDot` + `MiniGaugeDots` primitives

**Files:**
- Create: `PRTracker/Views/Mail/UnreadDot.swift`
- Create: `PRTracker/Views/Mail/MiniGaugeDots.swift`

Small reusable views used inside `MailRowView`.

- [ ] **Step 1: Create `UnreadDot`**

Create `PRTracker/Views/Mail/UnreadDot.swift`:

```swift
import SwiftUI

/// 8pt unread indicator. When `on`, shows a solid `unreadDot` fill plus a soft 2pt ring.
/// When `off`, occupies the same space transparently so layout doesn't shift.
struct UnreadDot: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? Tokens.unreadDot : .clear)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(on ? Tokens.unreadDot.opacity(0.22) : .clear, lineWidth: 2)
                    .padding(-1)
            )
    }
}
```

- [ ] **Step 2: Create `MiniGaugeDots`**

Create `PRTracker/Views/Mail/MiniGaugeDots.swift`:

```swift
import SwiftUI

/// Three 7pt circles: Review → CI → Merge. Each dot is filled when its stage has a state,
/// outlined when empty. A pulsing animation plays on running dots.
struct MiniGaugeDots: View {
    let pr: PullRequest

    private enum DotState { case empty, passed, failed, running, neutral }

    var body: some View {
        HStack(spacing: 3) {
            dot(for: reviewState)
            dot(for: ciState)
            dot(for: mergeState)
        }
        .help(tooltip)
    }

    @ViewBuilder
    private func dot(for state: DotState) -> some View {
        switch state {
        case .empty:
            Circle().stroke(Tokens.borderStrong, lineWidth: 1).frame(width: 7, height: 7)
        case .passed:
            Circle().fill(Tokens.approved).frame(width: 7, height: 7)
        case .failed:
            Circle().fill(Tokens.changes).frame(width: 7, height: 7)
        case .running:
            Circle().fill(Tokens.pending).frame(width: 7, height: 7)
                .modifier(PulseModifier())
        case .neutral:
            Circle().fill(Tokens.commented).frame(width: 7, height: 7)
        }
    }

    private var reviewState: DotState {
        switch pr.reviewState {
        case .approved:          .passed
        case .changesRequested:  .failed
        case .commented:         .neutral
        case .pending, .none:    .empty
        }
    }

    private var ciState: DotState {
        if pr.ciFail > 0 { return .failed }
        if pr.ciRunning > 0 { return .running }
        if pr.ciPass > 0 { return .passed }
        return .empty
    }

    private var mergeState: DotState {
        switch pr.mergeable {
        case .clean:     .passed
        case .conflicts, .blocked: .failed
        case .unknown:   .empty
        }
    }

    private var tooltip: String {
        "Review \(label(reviewState)) · CI \(label(ciState)) · Merge \(label(mergeState))"
    }

    private func label(_ s: DotState) -> String {
        switch s {
        case .empty:   "—"
        case .passed:  "passed"
        case .failed:  "failed"
        case .running: "running"
        case .neutral: "commented"
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
```

- [ ] **Step 3: Verify the project still builds**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Views/Mail/UnreadDot.swift PRTracker/Views/Mail/MiniGaugeDots.swift
git commit -m "feat(mail): UnreadDot and MiniGaugeDots primitives"
```

---

## Task 9: `MailRowView`

**Files:**
- Create: `PRTracker/Views/Mail/MailRowView.swift`

The real row that replaces the placeholder `Text` in `MailSourceColumn`. Includes priority rail, unread dot, title/time, second line of avatar/author/#num/spacer/MergedPill-or-MiniGaugeDots, optional hint snippet, and the right-click context menu.

- [ ] **Step 1: Create `MailRowView`**

Create `PRTracker/Views/Mail/MailRowView.swift`:

```swift
import SwiftUI

struct MailRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let onToggleRead: () -> Void

    @State private var hover = false

    private var bucket: Section? {
        // Reuse the existing Classifier output by recomputing here.
        // For row display we only need the Lane, so we just match the same priority chain
        // by reading the hints + state. If `Classifier.section(for:viewer:mentions:now:)`
        // produced this PR, the lane mapping below is identical.
        if pr.attentionHint != nil { return .attention }
        if pr.mentionHint   != nil { return .mentions }
        if pr.involvedHint  != nil { return .involved }
        switch pr.state {
        case .merged: return .recent
        case .open:
            if pr.reviewState == nil && pr.reviewers.contains(where: { $0.user.login == "" }) { return .review }
            return .mine
        default: return nil
        }
    }

    private var laneColor: Color { (bucket?.lane.color) ?? Tokens.textFaint }

    var body: some View {
        ZStack(alignment: .leading) {
            // Priority rail
            RoundedRectangle(cornerRadius: 2)
                .fill(laneColor)
                .frame(width: 3)
                .padding(.vertical, 6)
                .opacity(pr.isUnread ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 4) {
                topLine
                bottomLine
                if let hint = preview {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .padding(.leading, 15)
                        .padding(.top, 1)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)
        .opacity(pr.isUnread || isSelected ? 1 : 0.62)
        .onHover { hover = $0 }
        .contextMenu {
            Button(pr.isUnread ? "Mark as read" : "Mark as unread", action: onToggleRead)
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: pr.isUnread)
    }

    private var rowBackground: Color {
        if isSelected { return Tokens.rowSelect }
        if hover { return Tokens.rowHover }
        return .clear
    }

    private var topLine: some View {
        HStack(alignment: .center, spacing: 7) {
            UnreadDot(on: pr.isUnread)
            Text(pr.title)
                .font(.system(size: 13, weight: pr.isUnread ? .bold : .medium))
                .foregroundStyle(isSelected ? Tokens.accentText : Tokens.text)
                .tracking(-0.05)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RelativeTimeFormatter.short(pr.updatedAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
                .lineLimit(1)
        }
    }

    private var bottomLine: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 16)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
                .lineLimit(1)
            Text("·")
                .foregroundStyle(Tokens.textFaint)
            Text("#\(pr.number)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
            Spacer(minLength: 0)
            if pr.state == .merged {
                mergedPill
            } else {
                MiniGaugeDots(pr: pr)
            }
        }
    }

    private var mergedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 10).weight(.semibold))
            Text("Merged").font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.51, green: 0.31, blue: 0.87))
    }

    private var preview: String? {
        pr.attentionHint ?? pr.mentionHint ?? pr.involvedHint
    }
}
```

- [ ] **Step 2: Wire `MailRowView` into the placeholder list**

Open `PRTracker/Views/Mail/MailSourceColumn.swift` and replace the inner `List` block:

```swift
            List(selection: $appState.selectedPRID) {
                ForEach(prs) { pr in
                    MailRowView(
                        pr: pr,
                        isSelected: appState.selectedPRID == pr.id,
                        onToggleRead: { toggleRead(pr) }
                    )
                    .tag(pr.id)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
```

And add the `toggleRead` helper plus the `syncActor` access. Update `MailSourceColumn` to receive a `syncActor`:

```swift
struct MailSourceColumn: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    // ... body unchanged except the List block above ...

    private func toggleRead(_ pr: PullRequest) {
        let id = pr.id
        let wasUnread = pr.isUnread
        Task {
            try? await syncActor.setLastReadAt(prID: id, date: wasUnread ? .now : nil)
        }
    }
}
```

Update the call site in `MainView`:

```swift
MailSourceColumn(syncActor: coordinator.syncActorForView, onOpenSettings: onOpenSettings)
```

- [ ] **Step 3: Verify the project builds**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify the row**

Run the app. Confirm:
- Rows show the title (bold when unread), avatar+author+number, time stamp, and the three MiniGaugeDots (or a Merged pill).
- Read rows fade to ~62% opacity.
- Right-clicking a row shows "Mark as read"/"Mark as unread" and toggling persists across launches.
- Selecting a row dims its background to `rowSelect` and switches the detail pane.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Mail/MailRowView.swift PRTracker/Views/Mail/MailSourceColumn.swift PRTracker/App/RootView.swift
git commit -m "feat(mail): MailRowView with priority rail, unread state, context menu"
```

---

## Task 10: `FilterPillBar` + `MailListView`

**Files:**
- Create: `PRTracker/Views/Mail/FilterPillBar.swift`
- Create: `PRTracker/Views/Mail/MailListView.swift`
- Modify: `PRTracker/Views/Mail/MailSourceColumn.swift`

Source list owns both the sticky filter strip and the scrollable rows.

- [ ] **Step 1: Create `FilterPillBar`**

Create `PRTracker/Views/Mail/FilterPillBar.swift`:

```swift
import SwiftUI

struct FilterPillBar: View {
    @Binding var active: MailFilter
    let counts: [MailFilter: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MailFilter.allCases) { filter in
                    pill(filter)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder
    private func pill(_ filter: MailFilter) -> some View {
        let isActive = (filter == active)
        Button {
            active = filter
        } label: {
            HStack(spacing: 5) {
                if let dot = filter.dotColor {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(filter.label).font(.system(size: 11.5, weight: .semibold))
                if let count = counts[filter], count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(isActive ? Tokens.contentBg.opacity(0.7) : Tokens.textMuted)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .foregroundStyle(isActive ? Tokens.contentBg : Tokens.text)
            .background(
                Capsule().fill(isActive ? Tokens.text : Tokens.cardBg)
            )
            .overlay(
                Capsule().stroke(isActive ? .clear : Tokens.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Create `MailListView`**

Create `PRTracker/Views/Mail/MailListView.swift`:

```swift
import SwiftUI
import SwiftData

struct MailListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor

    var body: some View {
        @Bindable var appState = appState
        let viewerLogin = viewerStates.first?.viewer?.login ?? ""
        let buckets = grouped(viewerLogin: viewerLogin)
        let counts = counts(from: buckets)
        let visible = visiblePRs(buckets: buckets, filter: appState.activeFilter)

        VStack(spacing: 0) {
            FilterPillBar(active: $appState.activeFilter, counts: counts)
            List(selection: $appState.selectedPRID) {
                if visible.isEmpty {
                    Text("Nothing in this filter.")
                        .font(.system(size: 12.5).italic())
                        .foregroundStyle(Tokens.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visible) { pr in
                        MailRowView(
                            pr: pr,
                            isSelected: appState.selectedPRID == pr.id,
                            onToggleRead: { toggleRead(pr) }
                        )
                        .tag(pr.id)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: appState.activeFilter) { _, _ in
            reconcileSelection(visiblePRs: visiblePRs(buckets: buckets, filter: appState.activeFilter))
        }
    }

    private func grouped(viewerLogin: String) -> [Section: [PullRequest]] {
        var out: [Section: [PullRequest]] = [:]
        let now = Date.now
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: pr.timeline.compactMap { $0.type == .comment ? $0.actor?.login : nil },
                updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: [], now: now) {
                out[s, default: []].append(pr)
            }
        }
        return out
    }

    private func counts(from buckets: [Section: [PullRequest]]) -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        var total = 0
        for filter in MailFilter.allCases where filter != .all {
            if let s = filter.section {
                let n = buckets[s]?.count ?? 0
                c[filter] = n
                total += n
            }
        }
        c[.all] = total
        return c
    }

    private func visiblePRs(buckets: [Section: [PullRequest]], filter: MailFilter) -> [PullRequest] {
        if let s = filter.section { return buckets[s] ?? [] }
        // .all — flatten across all buckets in display order (already sorted by updatedAt desc by the @Query).
        var seen = Set<String>(); var out: [PullRequest] = []
        for s in Section.allCases {
            for pr in buckets[s] ?? [] where !seen.contains(pr.id) {
                seen.insert(pr.id); out.append(pr)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func reconcileSelection(visiblePRs: [PullRequest]) {
        let ids = visiblePRs.map(\.id)
        appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: ids)
    }

    private func toggleRead(_ pr: PullRequest) {
        let id = pr.id
        let wasUnread = pr.isUnread
        Task {
            try? await syncActor.setLastReadAt(prID: id, date: wasUnread ? .now : nil)
        }
    }
}
```

- [ ] **Step 3: Update `MailSourceColumn` to use `MailListView`**

Open `PRTracker/Views/Mail/MailSourceColumn.swift`. Replace the placeholder `List` block (and the `prs` `@Query` since it now lives in `MailListView`) with `MailListView`. The whole file becomes:

```swift
import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // TODO(Task 11): replace with RepoSelectorCard
            Text("Repo Selector").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)

            MailListView(syncActor: syncActor)

            // TODO(Task 12): replace with AccountFooter
            Divider()
            HStack { Text("Account").font(.system(size: 11)); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
```

- [ ] **Step 4: Verify the project builds**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manually verify the pills**

Run the app. Confirm:
- The pill strip shows All / Attention / Review / Mentions / Mine / Involved / Merged.
- Active pill inverts (dark background, light text in light mode).
- Counts appear right of the label and hide when zero.
- Switching filters changes the list and reconciles selection (keeps the selected PR if still in the list; else picks the first; else shows "Nothing in this filter.").

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Mail/FilterPillBar.swift PRTracker/Views/Mail/MailListView.swift PRTracker/Views/Mail/MailSourceColumn.swift
git commit -m "feat(mail): FilterPillBar + MailListView with bucket counts and selection reconcile"
```

---

## Task 11: `RepoSelectorCard`

**Files:**
- Create: `PRTracker/Views/Mail/RepoSelectorCard.swift`
- Modify: `PRTracker/Views/Mail/MailSourceColumn.swift`

- [ ] **Step 1: Create the card**

Create `PRTracker/Views/Mail/RepoSelectorCard.swift`:

```swift
import SwiftUI

struct RepoSelectorCard: View {
    let repoSlug: String   // "oreilly/spark-ios"
    let onTap: () -> Void

    private var org: String { repoSlug.split(separator: "/").first.map(String.init) ?? "" }
    private var name: String { repoSlug.split(separator: "/").dropFirst().joined(separator: "/") }
    private var initials: String { name.prefix(2).uppercased() }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.79, green: 0.39, blue: 0.26),
                                     Color(red: 0.48, green: 0.18, blue: 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Text(initials).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(org).font(.system(size: 11)).foregroundStyle(Tokens.textMuted).lineLimit(1)
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Wire it into `MailSourceColumn`**

Open `PRTracker/Views/Mail/MailSourceColumn.swift`. Add a `@Query` for `Repo`, and replace the placeholder `Text("Repo Selector")` block with `RepoSelectorCard`. Full file:

```swift
import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        let repo = repos.first(where: \.isActive)
        VStack(spacing: 0) {
            RepoSelectorCard(repoSlug: repo?.id ?? "—", onTap: onOpenSettings)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)

            MailListView(syncActor: syncActor)

            // TODO(Task 12): replace with AccountFooter
            Divider()
            HStack { Text("Account").font(.system(size: 11)); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
```

- [ ] **Step 3: Verify build**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify**

Run the app. Confirm the repo card shows org/name and tapping it opens Settings.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Mail/RepoSelectorCard.swift PRTracker/Views/Mail/MailSourceColumn.swift
git commit -m "feat(mail): RepoSelectorCard (taps to open Settings)"
```

---

## Task 12: `AccountFooter`

**Files:**
- Create: `PRTracker/Views/Mail/AccountFooter.swift`
- Modify: `PRTracker/Views/Mail/MailSourceColumn.swift`

- [ ] **Step 1: Create the footer**

Create `PRTracker/Views/Mail/AccountFooter.swift`:

```swift
import SwiftUI

struct AccountFooter: View {
    let viewer: User?
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let viewer {
                AvatarView(user: viewer, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewer.name ?? viewer.login)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.text)
                        .lineLimit(1)
                    Text("@\(viewer.login)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(1)
                }
            } else {
                Text("Not signed in").font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 0)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .top)
    }
}
```

- [ ] **Step 2: Wire it into `MailSourceColumn`**

Open `PRTracker/Views/Mail/MailSourceColumn.swift`. Add a `@Query` for `ViewerState`, replace the placeholder footer. Full file:

```swift
import SwiftUI
import SwiftData

struct MailSourceColumn: View {
    @Query private var repos: [Repo]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor
    var onOpenSettings: () -> Void

    var body: some View {
        let repo = repos.first(where: \.isActive)
        let viewer = viewerStates.first?.viewer
        VStack(spacing: 0) {
            RepoSelectorCard(repoSlug: repo?.id ?? "—", onTap: onOpenSettings)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)

            MailListView(syncActor: syncActor)

            AccountFooter(viewer: viewer, onOpenSettings: onOpenSettings)
        }
        .frame(width: 380)
        .background(Tokens.sidebarBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .trailing)
    }
}
```

- [ ] **Step 3: Verify build & manually check footer**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Run the app and confirm the footer shows your avatar/name/@login and the gear opens Settings.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Views/Mail/AccountFooter.swift PRTracker/Views/Mail/MailSourceColumn.swift
git commit -m "feat(mail): AccountFooter with avatar + login + settings gear"
```

---

## Task 13: `MailEmptyDetailView`

**Files:**
- Create: `PRTracker/Views/Mail/MailEmptyDetailView.swift`
- Modify: `PRTracker/App/RootView.swift`

- [ ] **Step 1: Create the empty view**

Create `PRTracker/Views/Mail/MailEmptyDetailView.swift`:

```swift
import SwiftUI

struct MailEmptyDetailView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 28))
                .foregroundStyle(Tokens.textFaint.opacity(0.5))
            Text("No pull request selected.")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.contentBg)
    }
}
```

- [ ] **Step 2: Swap the placeholder**

In `PRTracker/App/RootView.swift`, replace `MailEmptyDetailViewPlaceholder()` with `MailEmptyDetailView()` and delete the placeholder struct.

- [ ] **Step 3: Verify build**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Views/Mail/MailEmptyDetailView.swift PRTracker/App/RootView.swift
git commit -m "feat(mail): real MailEmptyDetailView replaces placeholder"
```

---

## Task 14: Rewrite `PRDetailView` header

**Files:**
- Create: `PRTracker/Views/Mail/MailDetailHeader.swift`
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`

Strip the back button, drop the inline "Open on GitHub" button (we keep the link, just move it), and rebuild the toolbar row per the spec.

- [ ] **Step 1: Create `MailDetailHeader`**

Create `PRTracker/Views/Mail/MailDetailHeader.swift`:

```swift
import SwiftUI

struct MailDetailHeader: View {
    let pr: PullRequest
    let isRefreshing: Bool
    let lastUpdatedAt: Date?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbarRow
            Text(pr.title)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.2)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            metadataRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Text(pr.repo.name).font(.system(size: 11.5)).foregroundStyle(Tokens.textFaint)
            Text("/").foregroundStyle(Tokens.textFaint)
            Text("#\(pr.number)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Tokens.textMuted)
            Text("·").foregroundStyle(Tokens.textFaint)
            statePill
            Spacer()
            updatedChip
            openOnGitHubLink
            refreshButton
        }
    }

    @ViewBuilder private var statePill: some View {
        let color = stateColor
        HStack(spacing: 4) {
            Image(systemName: stateIcon).font(.system(size: 11, weight: .semibold))
            Text(stateLabel).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 1)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    @ViewBuilder private var updatedChip: some View {
        if isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Refreshing…").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            }
        } else if let t = lastUpdatedAt {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 11))
                Text("Updated \(RelativeTimeFormatter.short(t))").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
            }
        }
    }

    private var openOnGitHubLink: some View {
        Link(destination: URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)")!) {
            HStack(spacing: 4) {
                Text("Open on GitHub").font(.system(size: 12, weight: .medium)).foregroundStyle(Tokens.text)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.textMuted)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.textMuted)
                .frame(width: 24, height: 24)
                .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help("Refresh")
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 18)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.text)
            Text("wants to merge into").foregroundStyle(Tokens.textMuted).font(.system(size: 11.5))
            Text(pr.branchBase)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
            Text("from").foregroundStyle(Tokens.textMuted).font(.system(size: 11.5))
            Text(pr.branchHead)
                .font(.system(size: 10.5).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 4))
            Text("·").foregroundStyle(Tokens.textFaint)
            Text("opened \(RelativeTimeFormatter.short(pr.openedAt))")
                .foregroundStyle(Tokens.textFaint).font(.system(size: 11))
        }
    }

    private var stateLabel: String {
        switch pr.state { case .open: "Open"; case .merged: "Merged"; case .closed: "Closed"; case .draft: "Draft" }
    }
    private var stateIcon: String {
        switch pr.state {
        case .open:   "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .draft:  "circle.dashed"
        }
    }
    private var stateColor: Color {
        switch pr.state {
        case .open:   Tokens.approved
        case .merged: Color(red: 0.51, green: 0.31, blue: 0.87)
        case .closed: Tokens.changes
        case .draft:  Tokens.textMuted
        }
    }
}
```

- [ ] **Step 2: Replace `PRDetailView.header` and trigger lastReadAt update**

Open `PRTracker/Views/Detail/PRDetailView.swift`. Replace the entire `private var header: some View { ... }` block and the helper computed properties (`stateLabel`, `stateIcon`, `stateColor`) with a single call:

```swift
    @ViewBuilder
    private var header: some View {
        MailDetailHeader(
            pr: pr,
            isRefreshing: isLoading,
            lastUpdatedAt: pr.updatedAt,
            onRefresh: { Task { await loadTimeline() } }
        )
    }
```

Then update the `.task(id: pr.id)` modifier on `body` to also mark the PR as read:

```swift
        .task(id: pr.id) {
            await loadTimeline()
            try? await syncActor.setLastReadAt(prID: pr.id, date: .now)
        }
```

- [ ] **Step 3: Verify build**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify**

Run the app. Select a PR. Confirm:
- The header shows breadcrumb (`repo · / · #num · status pill`), "Updated Xm ago" chip, "Open on GitHub" link, refresh button.
- No back button.
- The unread dot on the row disappears once selection lands.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Mail/MailDetailHeader.swift PRTracker/Views/Detail/PRDetailView.swift
git commit -m "feat(detail): MailDetailHeader replaces back-button header, marks PR read on open"
```

---

## Task 15: Fidelity pass on `TimelineColumn` and `TimelineEventRow`

**Files:**
- Modify: `PRTracker/Views/Detail/TimelineColumn.swift`
- Modify: `PRTracker/Views/Detail/TimelineEventRow.swift`

Two refinements per spec §Detail body:
1. Vertical 1pt hairline rail at `leading: 13` from top to bottom of the timeline.
2. Each event dot has a 2pt `contentBg` border (cutout-from-rail effect). Seen events render at `opacity: 0.48`; new events get a 4pt accent bar at `leading: -4` and a 3pt accent ring on the dot.

These files exist — open them and adjust. Because the existing code structures differ, this task is a guided edit rather than a verbatim replacement.

- [ ] **Step 1: Read the current files**

```bash
sed -n '1,60p' PRTracker/Views/Detail/TimelineColumn.swift
sed -n '1,80p' PRTracker/Views/Detail/TimelineEventRow.swift
```

- [ ] **Step 2: Add the vertical rail to `TimelineColumn`**

In `PRTracker/Views/Detail/TimelineColumn.swift`, wrap the existing root `VStack` (or whatever container holds the events) in a `ZStack(alignment: .topLeading)`. Insert before the events:

```swift
            Rectangle()
                .fill(Tokens.hairline)
                .frame(width: 1)
                .padding(.leading, 13)
```

The rail spans the full timeline height and sits behind the dots.

- [ ] **Step 3: Adjust `TimelineEventRow` dot styling**

In `PRTracker/Views/Detail/TimelineEventRow.swift`, find the `Circle()` that renders the event dot (size ~20pt). Apply:

```swift
            Circle()
                .fill(dotColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Tokens.contentBg, lineWidth: 2))
                .overlay(Circle().stroke(Tokens.accent.opacity(0.22), lineWidth: 3).opacity(event.isSeen ? 0 : 1))
                .padding(.leading, 4)
```

Set the row's overall opacity from `1.0` → `0.48` when `event.isSeen == true`. If the row supports an "is new" indicator, add a 4pt accent bar:

```swift
            Rectangle()
                .fill(Tokens.accent)
                .frame(width: 4)
                .padding(.leading, -4)
                .opacity(event.isSeen ? 0 : 1)
```

Content area uses `padding(.leading, 38)`.

- [ ] **Step 4: Verify build & manually check**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Manually: open a PR with several timeline events. Confirm the vertical rail draws through the column with dots punched through it, seen events dim to ~48%, and unseen events have an accent ring/bar.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Detail/TimelineColumn.swift PRTracker/Views/Detail/TimelineEventRow.swift
git commit -m "feat(detail): timeline rail, dot cutout, seen-event 0.48 dim, new-event accent ring"
```

---

## Task 16: Reorganize `DetailRightRail` — sections + "Mark as unread"

**Files:**
- Modify: `PRTracker/Views/Detail/DetailRightRail.swift`

The rail today has "Mark all seen / Mark all unseen" buttons. Replace them with a single full-width "Mark as unread" button that calls `syncActor.setLastReadAt(prID:, date: nil)`. Ensure the section order is: Status → CI checks → Reviewers → Labels → Changes → Mark as unread.

- [ ] **Step 1: Identify the current bottom buttons**

```bash
grep -n "Mark all" PRTracker/Views/Detail/DetailRightRail.swift
```

- [ ] **Step 2: Replace with the single button**

In `PRTracker/Views/Detail/DetailRightRail.swift`, locate the closing section of the rail (the `HStack` or VStack containing "Mark all seen" / "Mark all unseen"). Replace with:

```swift
            Button {
                onMarkUnread()
            } label: {
                Text("Mark as unread")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
```

Add the `onMarkUnread` closure to the rail's init parameters:

```swift
    let onMarkUnread: () -> Void
```

Remove the two `onMarkAllSeen` / `onMarkAllUnseen` parameters (and any internal state they tracked).

- [ ] **Step 3: Update the call site in `PRDetailView`**

In `PRTracker/Views/Detail/PRDetailView.swift`, change the existing call:

```swift
DetailRightRail(pr: pr,
    onMarkAllSeen: { ... },
    onMarkAllUnseen: { ... })
```

to:

```swift
DetailRightRail(pr: pr,
    onMarkUnread: {
        Task { try? await syncActor.setLastReadAt(prID: pr.id, date: nil) }
    })
```

- [ ] **Step 4: Confirm section order**

Inside `DetailRightRail`, verify the visual order of section blocks is: **Status, CI checks, Reviewers, Labels, Changes, Mark as unread**. Reorder by moving the corresponding view blocks if needed.

- [ ] **Step 5: Verify build & manually check**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Manually: open a PR. Confirm the rail's sections appear in the listed order and the "Mark as unread" button at the bottom flips the row's unread state.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Detail/DetailRightRail.swift PRTracker/Views/Detail/PRDetailView.swift
git commit -m "feat(detail): rail reordered to spec, single 'Mark as unread' button"
```

---

## Task 17: Settings — theme picker + apply at root

**Files:**
- Modify: `PRTracker/Models/ViewerState.swift`
- Modify: `PRTracker/Views/Settings/SettingsView.swift`
- Modify: `PRTracker/App/RootView.swift`

Persist a `themePreferenceRaw` ("system" / "light" / "dark") on `ViewerState`. Apply at the `RootView` level via `.preferredColorScheme`. Picker in the General tab.

- [ ] **Step 1: Add the field to `ViewerState`**

Open `PRTracker/Models/ViewerState.swift`. Add the field and matching computed accessor:

```swift
    var themePreferenceRaw: String = "system"

    enum ThemePreference: String { case system, light, dark }
    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }
```

Also extend `init` to accept the new field:

```swift
    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2,
         launchAtLoginEnabled: Bool = false, themePreferenceRaw: String = "system") {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.themePreferenceRaw = themePreferenceRaw
    }
```

- [ ] **Step 2: Add the Picker in Settings General tab**

In `PRTracker/Views/Settings/SettingsView.swift`, inside `generalTab`'s `VStack(alignment: .leading, spacing: 14)`, append (after the existing controls):

```swift
            Picker("Theme", selection: Binding(
                get: { vs.themePreference },
                set: { newValue in
                    vs.themePreference = newValue
                    try? ctx.save()
                })) {
                Text("System").tag(ViewerState.ThemePreference.system)
                Text("Light").tag(ViewerState.ThemePreference.light)
                Text("Dark").tag(ViewerState.ThemePreference.dark)
            }
            .pickerStyle(.menu)
```

- [ ] **Step 3: Apply `preferredColorScheme` at the root**

In `PRTracker/App/RootView.swift`, in `RootView.body`, after the outer `Group`, add:

```swift
        .preferredColorScheme({
            let raw = viewerStates.first?.themePreferenceRaw ?? "system"
            switch raw {
            case "light": return .light
            case "dark":  return .dark
            default:      return nil
            }
        }())
```

(Adjust placement so the modifier applies to the outermost view that owns the window content.)

- [ ] **Step 4: Verify build & manually check**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Manually: open Settings → General. Pick Light, Dark, System. Confirm the app's theme switches immediately on each selection.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Models/ViewerState.swift PRTracker/Views/Settings/SettingsView.swift PRTracker/App/RootView.swift
git commit -m "feat(settings): theme picker (system/light/dark) persisted on ViewerState"
```

---

## Task 18: Onboarding token + typography pass

**Files:**
- Modify: `PRTracker/Views/Onboarding/OnboardingView.swift`

Visual refresh — no flow change.

- [ ] **Step 1: Read the current file**

```bash
sed -n '1,200p' PRTracker/Views/Onboarding/OnboardingView.swift
```

- [ ] **Step 2: Apply the token sweep**

In each card/section:
- Container backgrounds → `Tokens.cardBg` with `RoundedRectangle(cornerRadius: 10)`, overlay `RoundedRectangle(cornerRadius: 10).stroke(Tokens.border, lineWidth: 0.5)`
- Titles → `.font(.system(size: 13, weight: .bold)).foregroundStyle(Tokens.text)`
- Secondary copy → `.font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tokens.textMuted)`
- Primary buttons → `.foregroundStyle(.white)`, `.background(Tokens.accent, in: RoundedRectangle(cornerRadius: 6))`
- Secondary buttons → `.background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 6))`, `.overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))`

Do not change input bindings, validation, or the navigation between onboarding steps.

- [ ] **Step 3: Verify build & manually check**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

If you can sign out / reset the keychain to re-enter onboarding, manually verify the look. If not, this step is best-effort visual; rely on the build.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Views/Onboarding/OnboardingView.swift
git commit -m "feat(onboarding): token + typography pass to match mail-redesign palette"
```

---

## Task 19: MenuBarExtra — compressed mail rows

**Files:**
- Modify: `PRTracker/Views/MenuBar/MenuBarContentView.swift`

A compressed row: priority rail (3pt) + UnreadDot · title (12/700 unread, 12/500 read) · time on a single line. No second line, no MiniGaugeDots, no hint snippet.

- [ ] **Step 1: Identify current row structure**

```bash
sed -n '1,200p' PRTracker/Views/MenuBar/MenuBarContentView.swift
```

- [ ] **Step 2: Replace each row's body**

Find the per-PR row inside `MenuBarContentView`. Replace its body with:

```swift
HStack(spacing: 0) {
    Rectangle()
        .fill(laneColor(for: pr))
        .frame(width: 3)
        .opacity(pr.isUnread ? 1 : 0.5)
    HStack(spacing: 7) {
        UnreadDot(on: pr.isUnread)
        Text(pr.title)
            .font(.system(size: 12, weight: pr.isUnread ? .bold : .medium))
            .foregroundStyle(Tokens.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(RelativeTimeFormatter.short(pr.updatedAt))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Tokens.textFaint)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
}
.opacity(pr.isUnread ? 1 : 0.62)
.background(Color.clear)
```

Provide a `laneColor(for:)` helper — reuse the same bucket-derivation used in `MailRowView`. If `MailRowView`'s helper isn't yet extracted, copy the same logic into a local `private func laneColor(for pr: PullRequest) -> Color` here.

If section headers exist in this view, style them as `Text("Header").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tokens.textFaint).textCase(.uppercase)`.

- [ ] **Step 3: Verify build & manually check**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Open the menubar dropdown. Confirm rows are compact, single-line, with the priority rail on the leading edge and the same read/unread fade behavior.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Views/MenuBar/MenuBarContentView.swift
git commit -m "feat(menubar): compressed mail-row style with priority rail and unread state"
```

---

## Task 20: Delete obsolete Feed/ files

**Files:**
- Delete: `PRTracker/Views/Feed/Sidebar.swift`
- Delete: `PRTracker/Views/Feed/FeedView.swift`
- Delete: `PRTracker/Views/Feed/FeedSection.swift`
- Delete: `PRTracker/Views/Feed/FeedToolbar.swift`
- Delete: `PRTracker/Views/Feed/PRCardView.swift`
- Delete: `PRTracker/Views/Feed/StatusGauge.swift`
- Modify: `PRTracker.xcodeproj/project.pbxproj` (to remove references)

- [ ] **Step 1: Confirm none of the deleted files are still referenced**

```bash
grep -rn "Sidebar\|FeedView\|FeedSection\|FeedToolbar\|PRCardView\|StatusGauge" PRTracker --include='*.swift'
```

Expected: zero matches in `PRTracker/` (matches in `handoff-mail/` and `docs/` are OK).

If anything still references these symbols, fix the reference before deleting (most likely a stale `import` or commented-out code).

- [ ] **Step 2: Delete the files**

```bash
git rm PRTracker/Views/Feed/Sidebar.swift \
       PRTracker/Views/Feed/FeedView.swift \
       PRTracker/Views/Feed/FeedSection.swift \
       PRTracker/Views/Feed/FeedToolbar.swift \
       PRTracker/Views/Feed/PRCardView.swift \
       PRTracker/Views/Feed/StatusGauge.swift
rmdir PRTracker/Views/Feed 2>/dev/null || true
```

- [ ] **Step 3: Open the project in Xcode (or use `xcodebuild`) and remove dangling references**

Xcode usually auto-cleans, but the `.pbxproj` may still reference deleted files. Open `PRTracker.xcodeproj/project.pbxproj` and remove any lines that mention the deleted filenames (they appear as `PBXFileReference` and `PBXBuildFile` entries). Alternatively, use Xcode's "Locate" → "Delete reference" for each file.

Verify with:

```bash
grep -c "Sidebar.swift\|FeedView.swift\|FeedSection.swift\|FeedToolbar.swift\|PRCardView.swift\|StatusGauge.swift" PRTracker.xcodeproj/project.pbxproj
```

Expected: `0`.

- [ ] **Step 4: Verify build**

Run:
```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PRTracker.xcodeproj/project.pbxproj
git commit -m "chore: delete obsolete Feed/ views replaced by mail layout"
```

---

## Task 21: Final smoke + test suite

**Files:** none

End-to-end verification before merging.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: all tests pass. New suites present: `PullRequestReadStateTests`, `MailFilterTests`, `SelectionReconcileTests`.

- [ ] **Step 2: Manual smoke**

Launch the app signed in. Walk through:
- Source list renders with repo card, filter pill bar, rows, account footer.
- Click each filter pill — counts correct, list re-filters, selection reconciles.
- Open a PR — unread dot disappears, row dims to 0.62, detail pane shows the new header.
- Right-click row → "Mark as unread" — unread dot returns.
- Empty filter — "Nothing in this filter." appears in the source list area and "No pull request selected." shows in the detail pane.
- Refresh in detail header — chip flashes "Refreshing…", returns to "Updated just now."
- Settings → General → Theme: switch System / Light / Dark — appearance updates instantly.
- MenuBarExtra dropdown — compressed rows readable; tap opens main window.

- [ ] **Step 3: Open a PR against `main`**

```bash
git log --oneline main..redesign | head -25
git push -u origin redesign
gh pr create --base main --title "Mail-style redesign" --body "$(cat <<'EOF'
## Summary
- Two-pane mail layout replaces Sidebar + Feed cards + drilled detail
- Read/unread derived from PullRequest.lastReadAt (new field)
- Restyled Settings (with Theme picker), Onboarding, and MenuBarExtra to the same palette
- Spec: docs/superpowers/specs/2026-05-19-mail-redesign-design.md
- Plan: docs/superpowers/plans/2026-05-19-mail-redesign.md

## Test plan
- [x] Unit tests pass (`xcodebuild ... test`)
- [ ] Manual smoke (see plan §21 Step 2)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

(Skip the `gh pr create` if you'd rather review locally first.)

---

## Self-Review

**Spec coverage:**
- §1 Goal — covered by overall plan
- §2 Approach — task order matches recommended phasing
- §3 Composition — Task 7 (shell), Task 17 (preferredColorScheme application)
- §4 Data model — Task 2 (lastReadAt + isUnread), Task 3 (SyncActor.setLastReadAt)
- §5 Components — Tasks 8 (UnreadDot, MiniGaugeDots), 9 (MailRowView), 10 (FilterPillBar, MailListView), 11 (RepoSelectorCard), 12 (AccountFooter), 13 (MailEmptyDetailView), 14 (MailDetailHeader), 15 (timeline fidelity), 16 (DetailRightRail)
- §6 Tokens — Task 1
- §7 Behavior — Task 9 (row tap + context menu), Task 10 (pill tap, reconcile), Task 14 (refresh + setLastReadAt on open), Task 16 (Mark as unread button)
- §8 Settings/Onboarding/MenuBar — Tasks 17 / 18 / 19
- §9 Removed code — Task 20
- §10 Testing — Tasks 2/3/4/5 (read state, syncActor, MailFilter, SelectionReconcile)
- §11 Risks — handled inline during implementation; manual smoke covers them
- §12 Out of scope — respected (no diff view, no multi-repo, no quick-reply submit, no palette variants)

**Placeholder scan:** No "TBD" / "implement later" / "add appropriate validation" patterns. Step bodies show concrete code or commands. The `MailRowView.bucket` helper in Task 9 contains a heuristic; that's a real implementation, not a placeholder (and the `MailListView` in Task 10 uses the authoritative `Classifier.section(...)` for filtering — the row's lane color is cosmetic).

**Type consistency:**
- `MailFilter` defined in Task 4 with cases `.all/.attention/.review/.mentions/.mine/.involved/.recent` — used consistently across Tasks 4, 10.
- `MailFilter.section` returns `Section?` — matches `Classifier`'s output type.
- `setLastReadAt(prID:date:)` signature stable across Tasks 3, 9, 14, 16.
- `MailSourceColumn` parameter list grows in two steps (Task 7 adds `onOpenSettings`, Task 9 adds `syncActor`); call sites are updated together.
- `DetailRightRail` parameter rename in Task 16 (`onMarkAllSeen`/`onMarkAllUnseen` → `onMarkUnread`) is done in the same task as the call-site update in `PRDetailView`.

No outstanding issues.
