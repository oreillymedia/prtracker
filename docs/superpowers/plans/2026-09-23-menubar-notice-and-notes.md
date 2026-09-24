# Menu-Bar Activity Notice + Private Notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work test-first where a test is listed.

**Goal:** (1) When new PR activity passes the existing per-repo notification policy, the menu-bar icon switches to a "new activity" variant until the user looks (opens the popover or activates the app). (2) The user can attach free-text private notes to a PR and to each conversation thread. Notes live only in the local SwiftData store and are never sent to GitHub.

**Architecture:** Both features ride on machinery that already exists.
- The notice reuses `NotificationDispatcher` (which already collects candidates, filters them through `NotificationPolicy`, and dedups via `NotificationLog`) and `BadgeController` (which already drives the menu-bar dot). The dispatcher gains one side effect: flag the badge controller when it finds new, policy-passing activity. The `MenuBarExtra` scene, commented out in `PRTrackerApp.swift` ("No menu app for now"), is re-enabled — there is no menu-bar icon today, so the feature needs it.
- Notes follow the existing "local-only field on a synced model" pattern (`isSeen`, `isDone`): a `note: String = ""` column on `PullRequest`, `TimelineEvent`, and `ReviewComment`. Sync upserts already only overwrite GitHub-sourced fields on existing rows, so notes survive refreshes with no sync changes. The `Thread` value type surfaces the root message's note; one small `NoteField` view renders it in `ThreadCard` and `DetailRightRail`.

**Tech Stack:** SwiftUI, SwiftData, AppKit (`NSImage`, `NSApplication` notifications), Swift Testing.

**Repo notes:** File-system-synchronized Xcode groups — new `.swift` files under `PRTracker/` or `PRTrackerTests/` are picked up automatically; do not edit `project.pbxproj`. Run tests with `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` (filter with `-only-testing:PRTrackerTests/<SuiteName>`). Follow the user's style rule: keep function signatures and initializer calls on one line, no one-parameter-per-line wrapping.

---

## Decisions (read before starting)

1. **"New activity" = exactly what `NotificationPolicy` would notify about**, per repo level (`personal` / `everything`; `.none` stays silent). No new policy code.
2. **The icon changes even when macOS notification permission is denied.** The auth check moves from a short-circuit to a "may post a banner" flag. `NotificationLog` rows are written either way so the same events don't re-flag on every sync. Consequence: events that arrive while permission is denied never later produce a banner. Acceptable — the icon told the user.
3. **The frontmost gate stays.** If the app is active when activity lands, neither banner nor icon change fires and no log rows are written (unchanged behavior). The next background sync re-evaluates.
4. **Clearing:** the flag resets when the app becomes active (`NSApplication.didBecomeActiveNotification`) or the menu-bar popover appears. Clicking a banner activates the app, so that path clears too.
5. **"Different icon" = the existing corner-dot composite, rendered as a template image.** Today `MenuBarIconRenderer` sets `isTemplate = false`, which draws a black glyph on a dark menu bar. Setting it to `true` makes both glyph and dot follow the menu bar's foreground color. Monochrome is the macOS convention; if a colored dot is wanted later, that's a one-line revert plus a proper dark-mode draw.
6. **`attentionCount` / Dock badge are untouched.** They're only fed from `MenuBarContentView.task`, which re-enabling the extra makes live again. Out of scope.
7. **Notes are stored on the root message of a thread**, not a separate model. Thread ids already map 1:1 to a root row: `te_<event>` / `rv_<event>` → `TimelineEvent`, `rc_<comment>` → root `ReviewComment`. A note dies with its row if GitHub deletes the comment (sync purges stale rows). Acceptable.
8. **PR-level note lives in the right rail** (`DetailRightRail`), top section, so it's visible without scrolling the thread list.
9. **Save on every change**, directly to the main `modelContext`, same as `isDone` toggles. No debounce. `// ponytail: per-keystroke save; debounce if typing ever stutters`.

Skipped (YAGNI): note indicator in the mail list row, notes in search, note history/timestamps, export.

---

## File Structure

**Feature 1 — menu-bar notice**
- `PRTracker/App/PRTrackerApp.swift` — **modify**: uncomment the `MenuBarExtra` scene; wire `d.badgeController = bc`.
- `PRTracker/Notifications/BadgeController.swift` — **modify**: add `hasNewActivity`, `noteNewActivity()`, `clearNewActivity()`; `menuBarShowsDot` keys off `hasNewActivity`; observe `didBecomeActiveNotification`.
- `PRTracker/Notifications/NotificationDispatcher.swift` — **modify**: `badgeController` property; auth becomes a `canPost` flag; flag badge on new filtered candidates.
- `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift` — **modify**: `isTemplate = true`.
- `PRTracker/Views/MenuBar/MenuBarContentView.swift` — **modify**: `.onAppear { controller.clearNewActivity() }`.
- `PRTrackerTests/Notifications/BadgeControllerTests.swift` — **modify**: 2 tests.
- `PRTrackerTests/Notifications/NotificationDispatcherTests.swift` — **modify**: 3 tests.

**Feature 2 — private notes**
- `PRTracker/Models/PullRequest.swift`, `TimelineEvent.swift`, `ReviewComment.swift` — **modify**: `var note: String = ""`.
- `PRTracker/Models/TodoHelpers.swift` — **modify**: `Thread.note`; populate in `threads(for:)`.
- `PRTracker/DesignSystem/NoteField.swift` — **create**: shared text field.
- `PRTracker/Views/Detail/ThreadCard.swift` — **modify**: note field in expanded body, note glyph in header, `onNoteChanged` callback.
- `PRTracker/Views/Detail/ThreadsView.swift` — **modify**: `setNote(_:for:)` mutation, pass callback.
- `PRTracker/Views/Detail/DetailRightRail.swift` — **modify**: "Notes" section bound to `pr.note`.
- `PRTrackerTests/Mail/TodoHelpersTests.swift` — **modify**: 1 test.
- `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`, `PRTrackerTests/Sync/SyncActorTests.swift` — **modify**: 1 test each.

---

## Task 1: `BadgeController.hasNewActivity`

**Files:**
- Modify: `PRTracker/Notifications/BadgeController.swift`
- Test: `PRTrackerTests/Notifications/BadgeControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `BadgeControllerTests`:

```swift
@Test func newActivityShowsMenuBarDot() {
    let c = BadgeController(dock: FakeDock())
    c.menuBarEnabled = true
    #expect(c.menuBarShowsDot == false)
    c.noteNewActivity()
    #expect(c.menuBarShowsDot == true)
    c.menuBarEnabled = false
    #expect(c.menuBarShowsDot == false)
}

@Test func clearNewActivityHidesDot() {
    let c = BadgeController(dock: FakeDock())
    c.noteNewActivity()
    c.clearNewActivity()
    #expect(c.menuBarShowsDot == false)
}
```

The existing `bothEnabledWithAttentionShowsBoth` and `togglingDockOffClearsLabel` tests assert `menuBarShowsDot == true` from `attentionCount = 3`. That coupling goes away; change those two assertions to check `dock.label` only, or add `c.noteNewActivity()` to them. Prefer the former — the menu-bar dot no longer means "attention count".

- [ ] **Step 2: Run tests, confirm they fail to compile** (`noteNewActivity` doesn't exist).

- [ ] **Step 3: Implement**

In `BadgeController`:

```swift
/// True from the moment a sync finds policy-passing activity until the user
/// looks: the popover opens or the app becomes active. Drives the menu-bar icon.
var hasNewActivity: Bool = false

var menuBarShowsDot: Bool { menuBarEnabled && hasNewActivity }

func noteNewActivity() { hasNewActivity = true }
func clearNewActivity() { hasNewActivity = false }
```

In `init`, alongside the existing `willTerminateNotification` observer:

```swift
NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
    self?.clearNewActivity()
}
```

Leave `attentionCount`, `dockShowsBadge`, and `apply()` as they are.

- [ ] **Step 4: Run `BadgeControllerTests`, confirm green.**

- [ ] **Step 5: Commit** — `feat(badge): track new-activity flag for menu-bar icon`

---

## Task 2: Dispatcher flags the badge

**Files:**
- Modify: `PRTracker/Notifications/NotificationDispatcher.swift`
- Test: `PRTrackerTests/Notifications/NotificationDispatcherTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `NotificationDispatcherTests`, reusing the suite's `setup`/`seedBaseline` helpers and the PR+comment fixture from `singleNewIssueCommentFires`:

```swift
@Test func newActivityFlagsBadge() async throws {
    // same fixture as singleNewIssueCommentFires (level .everything, one new comment by "iris")
    let badge = BadgeController(dock: BadgeControllerTests.FakeDock())
    let dispatcher = NotificationDispatcher(modelContainer: container, poster: CapturingPoster(), auth: StubAuth(status: .authorized), activity: StubActivityProbe(frontmost: false))
    dispatcher.badgeController = badge
    await dispatcher.process(repoID: repo.id)
    #expect(badge.hasNewActivity == true)
}

@Test func authDeniedStillFlagsBadgeAndWritesLogs() async throws {
    // same fixture; StubAuth(status: .denied)
    // expect: poster.posted.isEmpty, badge.hasNewActivity == true,
    //         NotificationLog count == 4 (3 baseline + comment_IC_1)
}

@Test func noNewActivityLeavesBadgeUntouched() async throws {
    // fixture with baseline only, no new events; StubAuth(.authorized)
    // expect: badge.hasNewActivity == false
}
```

`FakeDock` is currently nested in `BadgeControllerTests`; either reference it as above or move it into `Fakes.swift`. Moving is cleaner (one line).

Update the existing `authDeniedShortCircuits` test: it still expects no posts, but if it fetches logs, expect them written now.

- [ ] **Step 2: Run, confirm failure.**

- [ ] **Step 3: Implement**

In `NotificationDispatcher`:

```swift
/// Set from `PRTrackerApp`; flagged when a sync finds policy-passing activity.
var badgeController: BadgeController?
```

In `process(repoID:)`, replace

```swift
if await auth.currentStatus() != .authorized { return }
```

with

```swift
// Permission gates banners only. The menu-bar notice and the dedup log
// don't need it — see plan decision 2.
let canPost = await auth.currentStatus() == .authorized
```

and after the per-PR frontmost re-check (`if await MainActor.run(body: { activity.isFrontmost() }) { continue }`), replace the unconditional `await poster.post(content)` with:

```swift
await MainActor.run { badgeController?.noteNewActivity() }
if canPost { await poster.post(content) }
```

Log writes stay unconditional. `backfillSilentBaseline` / `baselineRepoThreads` are untouched (they must never flag the badge).

- [ ] **Step 4: Run `NotificationDispatcherTests`, confirm green.**

- [ ] **Step 5: Commit** — `feat(notify): flag menu-bar badge on new policy-passing activity`

---

## Task 3: Re-enable the menu-bar extra and wire it

**Files:**
- Modify: `PRTracker/App/PRTrackerApp.swift`
- Modify: `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift`
- Modify: `PRTracker/Views/MenuBar/MenuBarContentView.swift`

- [ ] **Step 1: `PRTrackerApp.init`** — after `self.coordinator.badgeController = self.badgeController`, add `d.badgeController = bc`.

- [ ] **Step 2: `PRTrackerApp.body`** — uncomment the `MenuBarExtra { … } label: { MenuBarLabel(controller: badgeController) }.menuBarExtraStyle(.window)` block verbatim.

- [ ] **Step 3: `MenuBarIconRenderer.image(showDot:)`** — change `composite.isTemplate = false` to `true`. The `NSColor(Tokens.accent).setFill()` line can stay (any opaque fill works for a template) or become `NSColor.black.setFill()`; either is fine.

- [ ] **Step 4: `MenuBarContentView`** — add `.onAppear { controller.clearNewActivity() }` next to the existing `.task(id: prs.count)`.

- [ ] **Step 5: Build and run.** Manual smoke:
  - Icon appears in the menu bar, plain glyph, correct in light and dark menu bars.
  - With the app in the background, have someone comment on a synced PR (or temporarily delete that comment's `NotificationLog` row in a debug build) → icon gains the dot within one sync interval.
  - Open the popover → dot clears. Repeat, then activate the main window instead → dot clears.
  - Settings → Notifications → "Show indicator on menu-bar icon" off → dot never shows.

- [ ] **Step 6: Commit** — `feat(menubar): re-enable menu-bar extra with new-activity icon`

---

## Task 4: `note` columns + sync preservation tests

**Files:**
- Modify: `PRTracker/Models/PullRequest.swift`, `PRTracker/Models/TimelineEvent.swift`, `PRTracker/Models/ReviewComment.swift`
- Test: `PRTrackerTests/Sync/SyncActorReviewCommentsTests.swift`, `PRTrackerTests/Sync/SyncActorTests.swift`

- [ ] **Step 1: Write the failing tests**

In `SyncActorReviewCommentsTests`, mirror `upsertPreservesIsSeen`:

```swift
@Test func upsertPreservesNote() async throws {
    // upsert sampleDTO(); set c.note = "ask about retries"; save; upsert sampleDTO(body: "Edited")
    // expect c2.note == "ask about retries" && c2.body == "Edited"
}
```

In `SyncActorTests`, mirror `upsertPreservesIsSeenOnExistingTimelineEvent` for `note`, and add one for the PR itself: upsert a PR DTO, set `pr.note`, upsert the same DTO again via `upsertPullRequests` and `updatePRStatistics`, expect the note intact.

- [ ] **Step 2: Run, confirm compile failure** (`note` doesn't exist).

- [ ] **Step 3: Add the columns**

Same doc comment on all three models, next to `isDone`:

```swift
/// Local-only — never sent to GitHub, never overwritten by sync. Free-text
/// private note the user attached in the app.
var note: String = ""
```

Default value → additive lightweight migration, same as `isDone` and `lastActivityAt` were. No `init` changes.

Verify by reading, not by editing: `SyncActor.upsertReviewComments` (existing-row branch, ~line 254) and `upsertTimeline` (~line 317) assign only GitHub fields; `upsertPullRequests` / `updatePRStatistics` likewise. Nothing to change — the tests prove it.

- [ ] **Step 4: Run both suites, confirm green.**

- [ ] **Step 5: Commit** — `feat(notes): add local-only note column to PR, timeline event, review comment`

---

## Task 5: Surface the note on `Thread`

**Files:**
- Modify: `PRTracker/Models/TodoHelpers.swift`
- Test: `PRTrackerTests/Mail/TodoHelpersTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func threads_carryRootNote() throws {
    let (ctx, pr, viewer) = try makePR()
    let root = makeReviewComment(in: pr, ctx: ctx, id: "rc1", author: viewer)
    root.note = "follow up Monday"
    _ = makeReviewComment(in: pr, ctx: ctx, id: "rc2", author: viewer, inReplyTo: "rc1")
    try ctx.save()
    let t = TodoHelpers.threads(for: pr, viewerLogin: "alex", lastSeenAt: nil).first { $0.id == "rc_rc1" }
    #expect(t?.note == "follow up Monday")
}
```

- [ ] **Step 2: Run, confirm failure.**

- [ ] **Step 3: Implement**

`Thread`: add `let note: String` and a `note: String = ""` parameter at the end of its `init` (keeps existing test call sites compiling). In `threads(for:)`, pass `note: e.note` for the `te_` and `rv_` threads and `note: root.note` for `rc_` threads.

Add a doc comment on `Thread.note`: "Private note on the thread's root row — `messages.first?.underlying` is the row to write back to."

- [ ] **Step 4: Run `TodoHelpersTests`, confirm green.**

- [ ] **Step 5: Commit** — `feat(notes): expose root note on Thread`

---

## Task 6: `NoteField` + thread and PR UI

**Files:**
- Create: `PRTracker/DesignSystem/NoteField.swift`
- Modify: `PRTracker/Views/Detail/ThreadCard.swift`, `PRTracker/Views/Detail/ThreadsView.swift`, `PRTracker/Views/Detail/DetailRightRail.swift`

- [ ] **Step 1: `NoteField`**

```swift
import SwiftUI

/// Private, local-only free text. Same look everywhere a note appears.
struct NoteField: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(Tokens.textFaint).padding(.top, 3)
            TextField("Private note — never sent to GitHub", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...8)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Tokens.contentBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
    }
}
```

- [ ] **Step 2: `ThreadCard`**

- Add `let onNoteChanged: (String) -> Void` (new init parameter, after `onResolveAll`).
- Add `@State private var noteDraft: String`, initialized from `thread.note` in `init`.
- In the expanded body, after the `ForEach(thread.messages)` and before `resolveFooter`:

```swift
NoteField(text: $noteDraft)
    .padding(.horizontal, 12).padding(.vertical, 8)
    .onChange(of: noteDraft) { _, new in onNoteChanged(new) }
```

- In `header`, before the GitHub `Link`, show a note glyph when the thread has one, so collapsed and resolved threads still hint at it:

```swift
if !thread.note.isEmpty {
    Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(Tokens.textMuted).help("Has a private note")
}
```

The `ForEach` in `ThreadsView` keys cards by `thread.id`, so `noteDraft` persists across re-renders of the same thread and re-seeds from the saved value if the card moves between OPEN and RESOLVED.

- [ ] **Step 3: `ThreadsView`**

Add, next to `toggle(message:)`:

```swift
private func setNote(_ text: String, for thread: Thread) {
    // ponytail: per-keystroke save; debounce if typing ever stutters
    switch thread.messages.first?.underlying {
    case .timelineEvent(let id): pr.timeline.first { $0.id == id }?.note = text
    case .reviewComment(let id): pr.reviewComments.first { $0.id == id }?.note = text
    case nil: return
    }
    try? ctx.save()
}
```

Pass `onNoteChanged: { setNote($0, for: thread) }` at both `ThreadCard(...)` call sites.

- [ ] **Step 4: `DetailRightRail`**

Change `let pr: PullRequest` to `@Bindable var pr: PullRequest`, add `@Environment(\.modelContext) private var ctx`, and insert as the first section:

```swift
section("Notes") {
    NoteField(text: $pr.note)
        .onChange(of: pr.note) { _, _ in try? ctx.save() }
}
```

- [ ] **Step 5: Build, run, manual smoke**
  - Type a note on a code-comment thread, on a discussion comment, and on a review summary; collapse/expand, switch PRs and back, quit and relaunch → notes persist and the header glyph shows on collapsed cards.
  - Type a PR note in the right rail; relaunch → persists.
  - Trigger "Refresh" in the detail toolbar → notes unchanged (sync preservation).
  - Confirm nothing in `GitHubClient` reads `note` (`grep -rn "\.note" PRTracker/GitHub` returns nothing).

- [ ] **Step 6: Run the full test suite.**

- [ ] **Step 7: Commit** — `feat(notes): private notes on threads and PRs`

---

## Done criteria

- Menu-bar icon present again; plain in steady state, dotted after policy-passing activity arrives while the app is in the background; clears on popover open or app activation; respects the existing menu-bar toggle in Settings.
- Notes editable on every thread card and in the PR right rail; survive sync, relaunch, and thread-state changes; never touch the network.
- All existing tests plus the 8 new ones green.

## Follow-ups (not in this plan)

- Note indicator in `MailRowView`, and notes included in sidebar search.
- Colored (non-template) dot with a proper dark-mode composite, if monochrome isn't enough.
- Dock badge semantics: `attentionCount` is only refreshed while the popover is open (`MenuBarContentView.task`). Pre-existing; move it to `SyncCoordinator` if the Dock badge should be trusted.
