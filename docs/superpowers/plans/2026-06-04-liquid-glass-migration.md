# Liquid Glass Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move PRTracker's UI onto standard SwiftUI navigation chrome (`NavigationSplitView`, `.toolbar`, `.inspector`) so it adopts Liquid Glass natively, and replace hand-rolled translucency with system-adaptive surfaces.

**Architecture:** The main window becomes a two-column `NavigationSplitView` (glass sidebar + detail) with the right rail as a toggleable `.inspector()` and detail actions in a glass `.toolbar`. The `Tokens` design system keeps its semantic *content* colors and repoints its *surface/separator* colors at AppKit system semantic colors (which adapt to Increase Contrast / Reduce Transparency for free). Glass is applied only to the navigation/control layer; content surfaces stay opaque.

**Tech Stack:** SwiftUI (macOS 26.4 / Xcode 26 SDK), SwiftData, AppKit semantic colors (`NSColor`).

---

## Testing philosophy for this plan

This is a view-layer refactor. The existing test suite (`PRTrackerTests`) covers model/sync/classifier/notification **logic**, not views — there are no view snapshot tests, and we are **not** adding any (YAGNI: glass rendering isn't meaningfully unit-testable and the logic is already covered). 

Therefore each task's verification gate is:
1. **Build succeeds:** `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
2. **Existing tests stay green:** `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
3. **Manual visual check** of the specific surface the task changed.

"Run the failing test first" does not apply here; the analogous discipline is "make the smallest change that compiles, confirm the suite is still green, then commit."

## Refinement vs. the approved spec (read before starting)

The spec said to retire `cardBg`/`contentBg` and convert ~40 content call sites to `.background(.background)` + `Divider()`. **This plan instead repoints the surface/separator tokens onto AppKit system semantic colors at the token layer (Task 1).** Same visual + accessibility outcome (system-adaptive surfaces, honors Increase Contrast), but ~40 fewer edits and far lower risk. The end state still has zero hand-tuned translucency. Structural separators in rewritten chrome files become real `Divider()`s as their containers turn into glass/inspector chrome (Tasks 2–4). `QuickReply.swift` is dead code (no references) and is left untouched.

## File map

| File | Change |
|---|---|
| `PRTracker/DesignSystem/Tokens.swift` | Repoint surface/separator tokens to system colors (Task 1); delete now-unused tokens (Task 8) |
| `PRTracker/App/RootView.swift` | `MainView` → `NavigationSplitView` (Task 2) |
| `PRTracker/Views/Mail/MailSourceColumn.swift` | Strip frame/bg/overlay; becomes sidebar content (Task 2) |
| `PRTracker/Views/Mail/MailEmptyDetailView.swift` | Remove `contentBg`; use `ContentUnavailableView` (Task 2) |
| `PRTracker/Views/Detail/PRDetailView.swift` | Add `.navigationTitle`, glass `.toolbar`, `.inspector` (Tasks 3–4) |
| `PRTracker/Views/Mail/MailDetailHeader.swift` | Slim to metadata + todo subheader; drop buttons/panel bg (Task 3) |
| `PRTracker/Views/Detail/DetailRightRail.swift` | Strip width/panel bg/border; wrap in `ScrollView` for inspector (Task 4) |
| `PRTracker/Views/Mail/MailListView.swift` | Remove `FilterPillBar`; add filter `Picker` to sidebar `.toolbar` (Task 5) |
| `PRTracker/Views/Mail/FilterPillBar.swift` | Deleted (Task 5) |
| `PRTracker/Views/Onboarding/OnboardingView.swift` | Glass buttons; system field surfaces (Task 6) |
| `PRTracker/Views/MenuBar/MenuBarContentView.swift` | Glass action buttons in `GlassEffectContainer`; system `Divider()` (Task 7) |

---

## Task 1: Repoint `Tokens` surface/separator colors to system semantic colors

**Files:**
- Modify: `PRTracker/DesignSystem/Tokens.swift:13-27` (and add a MARK)

- [ ] **Step 1: Replace the surface + separator token definitions**

In `Tokens.swift`, replace the existing `windowBg`, `panelBg`, `contentBg`, `sidebarBg`, `border`, `borderStrong`, `hairline` declarations (lines 14–27) with system-backed definitions. Leave **every other token unchanged** (accent, approved, changes, pending, commented, text/textMuted/textFaint, *Bg tints, rowHover, rowSelect, unreadDot, newHighlight).

Replace these lines:

```swift
    static let windowBg     = Color(nsColor: .dynamic(light: .white,
                                                       dark:  NSColor(white: 0.11, alpha: 1)))
    static let panelBg      = Color(nsColor: .dynamic(light: NSColor(white: 0.96, alpha: 0.85),
                                                       dark:  NSColor(white: 0.11, alpha: 0.85)))
    static let contentBg    = Color(nsColor: .dynamic(light: .white,
                                                       dark:  NSColor(white: 0.11, alpha: 1)))
    static let sidebarBg    = Color(nsColor: .dynamic(light: NSColor(red: 0.82, green: 0.88, blue: 0.96, alpha: 0.45),
                                                       dark:  NSColor(white: 0.17, alpha: 0.55)))
    static let border       = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.08),
                                                       dark:  NSColor(white: 1,   alpha: 0.10)))
    static let borderStrong = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.14),
                                                       dark:  NSColor(white: 1,   alpha: 0.16)))
    static let hairline     = Color(nsColor: .dynamic(light: NSColor(white: 0,   alpha: 0.06),
                                                       dark:  NSColor(white: 1,   alpha: 0.06)))
```

with:

```swift
    // MARK: - System-backed surfaces & separators
    // Formerly hand-tuned translucency that simulated depth. Now mapped onto
    // AppKit semantic colors so they adapt to Increase Contrast / Reduce
    // Transparency automatically. Glass for the navigation layer is provided by
    // NavigationSplitView / .inspector / .toolbar — not by these tokens.
    static let windowBg     = Color(nsColor: .windowBackgroundColor)
    static let panelBg      = Color(nsColor: .windowBackgroundColor)   // transitional; uses removed in Tasks 3–4
    static let sidebarBg    = Color(nsColor: .windowBackgroundColor)   // transitional; use removed in Task 2
    static let contentBg    = Color(nsColor: .textBackgroundColor)     // inset field / nested block surface
    static let border       = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .separatorColor)
    static let hairline     = Color(nsColor: .separatorColor).opacity(0.6)
```

Then, separately, change the existing `cardBg` declaration (line 45) — `.dynamic(light: .white, dark: NSColor(white: 0.17, alpha: 1))` — to a system surface:

```swift
    static let cardBg       = Color(nsColor: .controlBackgroundColor)
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (no call sites changed; all token names still exist).

- [ ] **Step 3: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 4: Manual visual check**

Launch the app. Confirm the window/sidebar/cards now use neutral system surfaces (the sidebar's blue wash is gone, replaced by the window background) and the app still renders correctly in light and dark mode.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/DesignSystem/Tokens.swift
git commit -m "refactor(tokens): repoint surface/separator tokens to system semantic colors"
```

---

## Task 2: Main window → `NavigationSplitView`

**Files:**
- Modify: `PRTracker/App/RootView.swift:74-99` (`MainView`)
- Modify: `PRTracker/Views/Mail/MailSourceColumn.swift` (whole file)
- Modify: `PRTracker/Views/Mail/MailEmptyDetailView.swift` (whole file)

- [ ] **Step 1: Convert `MailSourceColumn` to plain sidebar content**

Replace the whole body of `MailSourceColumn.swift` with (drops fixed width, `sidebarBg`, and the manual trailing border — the split view supplies sidebar chrome; a `Divider()` separates the footer):

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

            Divider()
            AccountFooter(viewer: viewer, onOpenSettings: onOpenSettings)
        }
    }
}
```

- [ ] **Step 2: Replace `MailEmptyDetailView` with `ContentUnavailableView`**

Replace the whole body of `MailEmptyDetailView.swift` (removes `Tokens.contentBg`; uses the system empty-state view which sits correctly on the detail background):

```swift
import SwiftUI

struct MailEmptyDetailView: View {
    var body: some View {
        ContentUnavailableView("No Pull Request Selected",
                               systemImage: "arrow.triangle.pull",
                               description: Text("Select a pull request from the sidebar."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Convert `MainView` to `NavigationSplitView`**

In `RootView.swift`, replace the `MainView` struct (lines 74–99) with:

```swift
struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query private var prs: [PullRequest]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        let viewer = viewerStates.first?.viewer

        NavigationSplitView {
            MailSourceColumn(syncActor: coordinator.syncActorForView, onOpenSettings: onOpenSettings)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, syncActor: coordinator.syncActorForView)
            } else {
                MailEmptyDetailView()
            }
        }
    }
}
```

(The `repos` query and `.navigationTitle(repo?.id ?? "")` from the old `MainView` are dropped here; the PR title becomes the window title in Task 3, and the repo name lives in `RepoSelectorCard`.)

> **Settings is in scope but needs no code changes.** `SettingsView` only references retained semantic tokens (`Tokens.textMuted`, `Tokens.changes`, `Tokens.textFaint`) and otherwise uses standard `Form`/`TabView`/`Picker`/`Toggle` controls, which restyle under the Xcode 26 SDK automatically. There is no Settings task; confirm it visually during Task 8.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (`Tokens.sidebarBg`/`contentBg` uses in these files are now gone.)

- [ ] **Step 5: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 6: Manual visual check**

Launch. Confirm: sidebar renders with native glass and is resizable; selecting a PR shows the detail; with no selection the `ContentUnavailableView` shows; keyboard up/down still moves selection in the list.

- [ ] **Step 7: Commit**

```bash
git add PRTracker/App/RootView.swift PRTracker/Views/Mail/MailSourceColumn.swift PRTracker/Views/Mail/MailEmptyDetailView.swift
git commit -m "feat(ui): main window to NavigationSplitView with glass sidebar"
```

---

## Task 3: Detail chrome → glass `.toolbar` + inline subheader

**Files:**
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`
- Modify: `PRTracker/Views/Mail/MailDetailHeader.swift` (whole file)

- [ ] **Step 1: Slim `MailDetailHeader` to a content subheader**

Replace the whole body of `MailDetailHeader.swift` with (drops `titleRow`, `refreshButton`, `openOnGitHubLink`, `updatedChip`, the `isRefreshing`/`onRefresh` params, and the `panelBg`; those actions move to the toolbar). Keeps the author/branch metadata + todo bar as content, with a trailing `Divider()`:

```swift
import SwiftUI

struct MailDetailHeader: View {
    let pr: PullRequest
    let todoCounts: TodoCounts
    let ciFailedForMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow
            if todoCounts.total > 0 || ciFailedForMe {
                TodoSummaryBar(counts: todoCounts, ciFailedForMe: ciFailedForMe)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Divider(), alignment: .bottom)
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
        }
    }
}
```

- [ ] **Step 2: Add navigation title, glass toolbar, and inspector state to `PRDetailView`**

In `PRDetailView.swift`, (a) add an inspector state property after `isLoading` (line 13):

```swift
    @State private var inspectorPresented: Bool = true
```

(b) Update the `MailDetailHeader(...)` call (lines 27–32) to its new signature:

```swift
            MailDetailHeader(pr: pr, todoCounts: todoCounts, ciFailedForMe: ciFailedForMe)
```

(c) Attach title + toolbar to the outer `VStack`. Change the `.task(id: pr.id) { await loadTimeline() }` modifier block (lines 47–49) so the modifiers read:

```swift
        .navigationTitle(pr.title)
        .navigationSubtitle("#\(pr.number)")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await loadTimeline() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(isLoading)

                Link(destination: URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)")!) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open on GitHub")
            }
            ToolbarItem {
                Button { inspectorPresented.toggle() } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle details")
            }
        }
        .task(id: pr.id) {
            await loadTimeline()
        }
```

(The `.inspector` modifier is added in Task 4; for now the `inspectorPresented` toggle compiles but has no visible effect — `DetailRightRail(pr: pr)` is still rendered inline in the `HStack` and is removed from there in Task 4.)

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 5: Manual visual check**

Launch, select a PR. Confirm: the window titlebar shows the PR title + `#number` with a glass toolbar carrying refresh / Open-on-GitHub / details-toggle buttons; refresh works and disables while loading; the subheader below shows author/branch metadata + todo bar with a divider.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Detail/PRDetailView.swift PRTracker/Views/Mail/MailDetailHeader.swift
git commit -m "feat(ui): detail chrome to glass toolbar + navigation title"
```

---

## Task 4: Right rail → `.inspector()`

**Files:**
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`
- Modify: `PRTracker/Views/Detail/DetailRightRail.swift:8-56`

- [ ] **Step 1: Strip rail chrome and make it inspector-ready**

In `DetailRightRail.swift`, change the `body` so the content scrolls and no longer paints its own width/panel background/border (the inspector supplies that chrome). Replace the outer container — i.e. the `VStack(alignment: .leading, spacing: 18) { ... }` plus its trailing `.padding(18)`, `.frame(width: 260)`, `.background(Tokens.panelBg)`, and `.overlay(...border...)` (lines 9 and 52–55) — with a `ScrollView` wrapper and only padding:

The body should open with:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
```

…unchanged section content…

and close with:

```swift
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
```

(Remove the `.frame(width: 260)`, `.background(Tokens.panelBg)`, and `.overlay(Rectangle().fill(Tokens.border)...)` modifiers entirely.)

- [ ] **Step 2: Move the rail into an `.inspector` and out of the detail `HStack`**

In `PRDetailView.swift`, remove `DetailRightRail(pr: pr)` from inside the `HStack(alignment: .top, spacing: 0)` (line 44) so the `HStack` contains only the `ScrollView`. (Optionally collapse the now-single-child `HStack` to just the `ScrollView`; leaving the `HStack` is also fine.)

Then add the inspector modifier directly after the `.navigationSubtitle("#\(pr.number)")` line from Task 3 (before `.toolbar`):

```swift
        .inspector(isPresented: $inspectorPresented) {
            DetailRightRail(pr: pr)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (`Tokens.panelBg` is now used by no one.)

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 5: Manual visual check**

Launch, select a PR. Confirm: the Status/CI/Reviewers/Labels/Changes rail now appears as a glass inspector on the trailing edge; the toolbar's details-toggle button shows/hides it with the standard slide animation; the rail scrolls if its content is tall.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/Detail/PRDetailView.swift PRTracker/Views/Detail/DetailRightRail.swift
git commit -m "feat(ui): right rail to toggleable glass inspector"
```

---

## Task 5: Filter pills → sidebar-toolbar `Picker`

**Files:**
- Modify: `PRTracker/Views/Mail/MailListView.swift:20-21` and add a `.toolbar`
- Delete: `PRTracker/Views/Mail/FilterPillBar.swift`

> **Design note (refinement of the spec's "segmented control"):** the app has 6 filters and shows per-filter counts, which won't fit a sidebar-width segmented control without losing the counts. This plan uses a **menu-style `Picker`** in the sidebar toolbar — compact, system-styled (so no glass-on-glass), and it preserves the counts in the menu labels. Same intent as the spec (filter selector lives in the toolbar). Flag for the reviewer at verification if a segmented control is preferred instead.

- [ ] **Step 1: Remove `FilterPillBar` from the list body**

In `MailListView.swift`, delete the `FilterPillBar(active: $appState.activeFilter, counts: counts)` line (line 21). The `VStack(spacing: 0)` now starts directly with the `ScrollView`. Keep the `let counts = pillCounts()` line — it now feeds the toolbar picker.

- [ ] **Step 2: Add the filter picker to the toolbar**

Attach a `.toolbar` to the `VStack` in `body` (it bubbles up to the enclosing `NavigationSplitView` sidebar column). Add it immediately after the `.onChange(of: appState.activeFilter)` modifier (currently ending at line 78):

```swift
        .toolbar {
            ToolbarItem {
                Picker("Filter", selection: $appState.activeFilter) {
                    ForEach(MailFilter.allCases) { filter in
                        Text(label(filter, count: counts[filter] ?? 0)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Filter pull requests")
            }
        }
```

- [ ] **Step 3: Add the label helper**

Add this method to `MailListView` (e.g. after `pillCounts()`):

```swift
    private func label(_ filter: MailFilter, count: Int) -> String {
        count > 0 ? "\(filter.label) (\(count))" : filter.label
    }
```

- [ ] **Step 4: Delete `FilterPillBar.swift`**

```bash
git rm PRTracker/Views/Mail/FilterPillBar.swift
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 7: Manual visual check**

Launch. Confirm: the filter selector appears in the sidebar toolbar as a glass menu showing the active filter; opening it lists all filters with counts; switching filters updates the list and reconciles selection as before.

- [ ] **Step 8: Commit**

```bash
git add PRTracker/Views/Mail/MailListView.swift
git commit -m "feat(ui): move PR filter into sidebar glass toolbar picker"
```

---

## Task 6: Glass buttons in Onboarding

**Files:**
- Modify: `PRTracker/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Convert the Validate button to glass**

In `OnboardingView.swift`, replace the `.token` stage's Validate button (lines 38–45) with:

```swift
                    Button("Validate") { Task { await validateToken() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(token.isEmpty || isValidating)
```

- [ ] **Step 2: Convert the Save button to glass**

Replace the `.repo` stage's Save button (lines 58–65) with:

```swift
                    Button("Save") { Task { await saveRepo() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(!ownerRepo.contains("/") || isValidating)
```

- [ ] **Step 3: Use system field surfaces and a standard text-field style**

Replace the two `SecureField`/`TextField` modifier stacks so they use a bordered field instead of the hand-rolled `contentBg`/`border` overlay.

For the `SecureField` (lines 30–37), replace with:

```swift
                    SecureField("ghp_…", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 420)
```

For the `TextField` (lines 50–57), replace with:

```swift
                    TextField("owner/name", text: $ownerRepo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 420)
```

- [ ] **Step 4: Replace the card container surface**

The card container modifiers (lines 74–76) use `cardBg` (already a system surface after Task 1) and a hand-drawn border. Replace them with a clean system surface in a rounded rectangle:

```swift
            .padding(16)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
```

(Drop the `.overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.border, lineWidth: 0.5))` line.)

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 7: Manual visual check**

To see onboarding, sign out (Settings → Account → Sign out) or run with a fresh data store. Confirm: the Validate/Save buttons render as prominent glass, fields are standard bordered fields, the card uses a neutral system surface.

- [ ] **Step 8: Commit**

```bash
git add PRTracker/Views/Onboarding/OnboardingView.swift
git commit -m "feat(ui): glass buttons and system surfaces in onboarding"
```

---

## Task 7: Menu-bar popover glass action buttons

**Files:**
- Modify: `PRTracker/Views/MenuBar/MenuBarContentView.swift:43-51` and the `menuButton`/`menuButtonLabel` helpers

- [ ] **Step 1: Group the action buttons in a `GlassEffectContainer` with glass styling**

In `MenuBarContentView.swift`, replace the footer action block (lines 43–51) with a glass container holding the actions. Replace:

```swift
            Divider()
            menuButton("Open PR Tracker", shortcut: nil) { openWindow(id: "main") }
            menuButton("Refresh now", shortcut: "⌘R") { Task { await coordinator.refresh() } }
            SettingsLink {
                menuButtonLabel("Preferences…", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            Divider()
            menuButton("Quit", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
```

with:

```swift
            Divider()
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    menuButton("Open PR Tracker", shortcut: nil) { openWindow(id: "main") }
                    menuButton("Refresh now", shortcut: "⌘R") { Task { await coordinator.refresh() } }
                    SettingsLink {
                        menuButtonLabel("Preferences…", shortcut: "⌘,")
                    }
                    .buttonStyle(.glass)
                    menuButton("Quit", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
```

- [ ] **Step 2: Switch `menuButton` to the glass button style**

Replace the `menuButton` helper (lines 122–126) with:

```swift
    private func menuButton(_ label: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuButtonLabel(label, shortcut: shortcut)
        }
        .buttonStyle(.glass)
    }
```

(The `menuButtonLabel` helper at lines 128–135 is unchanged.)

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 5: Manual visual check**

Click the menu-bar icon. Confirm: the PR list above is unchanged (content, no glass), and the bottom action buttons render as a grouped glass cluster; each action still works (Open, Refresh, Preferences, Quit). If the full-width glass buttons look heavy, note it for the reviewer — the fallback is reverting `menuButton` to `.plain` and keeping glass only on the container.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Views/MenuBar/MenuBarContentView.swift
git commit -m "feat(ui): glass action buttons in menu-bar popover"
```

---

## Task 8: Delete dead tokens + full accessibility verification

**Files:**
- Modify: `PRTracker/DesignSystem/Tokens.swift`

- [ ] **Step 1: Confirm `panelBg`, `sidebarBg`, `windowBg` are now unused**

Run:

```bash
grep -rn "Tokens.panelBg\|Tokens.sidebarBg\|Tokens.windowBg" PRTracker | grep '\.swift:'
```

Expected: no output. (All uses were removed in Tasks 1–4.) If any remain, resolve them before deleting.

- [ ] **Step 2: Delete the three transitional tokens**

In `Tokens.swift`, delete the `windowBg`, `panelBg`, and `sidebarBg` declarations added in Task 1. Leave `contentBg`, `cardBg`, `border`, `borderStrong`, `hairline` (still in use) and all semantic colors.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 5: Manual accessibility verification**

Launch the app and, in System Settings → Accessibility → Display, toggle each of the following, confirming the UI stays legible and glass degrades gracefully (chrome becomes opaque/higher-contrast; no unreadable text; no broken layout) across the main window (sidebar, toolbar, inspector), menu-bar popover, onboarding, and the Settings window (open Preferences, click through all four tabs):
- Reduce Transparency
- Increase Contrast
- Reduce Motion (confirm inspector/toolbar glass animations are tamed)

Repeat the main-window check in both light and dark mode.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/DesignSystem/Tokens.swift
git commit -m "refactor(tokens): remove transitional surface tokens after glass migration"
```

---

## Done

At this point the app is fully on standard navigation chrome with Liquid Glass: a `NavigationSplitView` glass sidebar, a glass detail toolbar, a toggleable glass inspector, a sidebar-toolbar filter picker, glass buttons in onboarding and the menu-bar popover, system-adaptive surfaces throughout, and verified accessibility behavior.
