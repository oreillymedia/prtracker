# Mail-style Redesign — Design Spec

**Status:** Approved for plan-writing
**Date:** 2026-05-19
**Branch:** `redesign`
**Reference:** `handoff-mail/README.md` and accompanying `*.jsx` prototypes

## 1. Goal

Replace the current three-pane Sidebar + Feed cards + drilled-into Detail layout with a **two-pane mail-style layout**: a 380pt filterable source list on the left, a permanent PR detail pane on the right. Selecting a row swaps the detail pane in place — no drilling, no slide-in.

The redesign covers the **entire app**: main window, Onboarding, Settings, and the MenuBarExtra dropdown all move onto the new token system and typography. Sync, GitHub client, Keychain, and the SwiftData model layer stay essentially untouched.

## 2. Migration approach

Incremental on the existing `redesign` branch, in this order. Each step compiles and produces a runnable app:

1. Extend `Tokens` with full light/dark palette and all new keys
2. Replace `MainView`'s `NavigationSplitView` with the two-pane shell + placeholder list rows
3. Build `MailListView` (filter pills sticky header + scrollable rows) and `MailRowView`
4. Rewrite the detail header; fidelity pass on `TimelineColumn`; reorganize `DetailRightRail`
5. Restyle Settings (add Theme picker), Onboarding, MenuBarExtra
6. Delete obsolete views (`Sidebar`, `FeedView`, `FeedSection`, `FeedToolbar`, `PRCardView`, parts of `StatusGauge`)
7. Tests for `MailFilter` bucket mapping, read-state derivation, selection reconcile

Old code is **deleted outright** — git history is the archive. No coexistence flag.

## 3. App composition

```
PRTrackerApp                     (unchanged)
 ├ WindowGroup → RootView        (unchanged: gates onboarding vs signed-in)
 │   └ MainView                  (rewritten)
 │       ├ MailSourceColumn      (380pt fixed, new)
 │       │   ├ RepoSelectorCard
 │       │   ├ MailListView      (filter pills + scrollable list)
 │       │   └ AccountFooter
 │       └ MailDetailPaneView    (flex, rewritten)
 │           or MailEmptyDetailView
 ├ MenuBarExtra → MenuBarContentView   (restyled)
 └ Settings → SettingsView             (theme picker added; restyled)
```

Window styling: **standard macOS title bar** (not hidden). Window title is bound to the active repo slug (e.g. `oreillymedia/puffin`) so the title bar isn't blank. Two panes sit beneath the title bar in an `HStack(spacing: 0)`. The source column is a **fixed 380pt width** (not user-resizable — `HSplitView` is explicitly avoided to keep the source list pinned); the detail pane fills the remainder. The detail slide-in transition shipped on this branch is removed — the detail pane is always visible.

### AppState

- **Remove:** `activeSection: Section?`
- **Add:** `activeFilter: MailFilter = .all`
- **Keep:** `selectedPRID: String?`

### MailFilter enum

```swift
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case all, attention, review, mentions, mine, involved, recent
    var id: String { rawValue }
}
```

Pill order matches the enum order. Labels: `All`, `Attention`, `Review`, `Mentions`, `Mine`, `Involved`, `Merged` (note `recent` → "Merged" label per spec).

## 4. Data model changes

### `PullRequest`

Add one field:

```swift
var lastReadAt: Date?
```

Redefine the existing computed property:

```swift
var isUnread: Bool {
    guard let lastReadAt else { return true }
    return updatedAt > lastReadAt
}
```

Per-event `isSeen` stays as-is — it still drives the 0.48-opacity dimming of seen events inside the timeline column. PR-level read is independent of event-level seen.

### SwiftData migration

Additive `var` with default `nil`. SwiftData handles automatically — no `VersionedSchema`/`SchemaMigrationPlan` required. Existing users see all PRs as unread on first launch; opening each marks it read.

### SyncActor additions

```swift
func setLastReadAt(prID: String, date: Date?) async throws
```

Called by:
- `MailDetailPaneView.task(id: pr.id)` — sets `.now` (alongside the existing `setSeenForPR(isSeen: true)` if we want to dim individual timeline events too — see Section 7 behavior)
- Row context menu "Mark as unread" → `nil`
- Row context menu "Mark as read" → `.now`

## 5. Components

### `MailSourceColumn` (new, container)

Vertical stack, 380pt fixed width, `sidebarBg` background with `border-right` 0.5pt `border`.

Children, top to bottom:
1. `RepoSelectorCard` — 12pt horizontal padding, 8pt top padding
2. `MailListView` — `flex: 1`, filter pills as a sticky header above the rows
3. `AccountFooter` — `border-top: 0.5pt border`, 10pt × 14pt padding

### `RepoSelectorCard`

Compact card: 22×22 logo tile (linear gradient `135°, #c96442 → #7b2d1a`, white "SP" 10pt 700), org/repo two-line text (`textMuted` 11pt over `text` 13/600), chevron-down at trailing edge.

Tap → calls `onOpenSettings()` (the existing `openSettings` environment closure plumbed through). Multi-repo dropdown is **out of scope**.

### `MailListView`

Owns both the filter pill bar and the scrollable rows.

**Sticky header — FilterPillBar:**
- 8pt top, 10pt bottom padding, 12pt horizontal, 6pt gap between pills
- `border-bottom: 0.5pt hairline`
- Horizontal scroll on overflow (hidden scrollbar)
- Per pill: `border-radius: 999`, padding `4×9×4×8`, font 11.5/600, 0.5pt `border` (inactive) or transparent (active). Inactive bg `cardBg`/text `text`; active bg `text`/text `contentBg` (inverts).
- 7pt dot left of label colored by `LANE_COLORS["roles"]` for the bucket. "All" pill has no dot.
- Count badge right of label: 10pt 700 `textMuted`. Hidden when 0.

Counts: single pass over `prs` per render, grouped by `Classifier.section(...)`. Memoize if profiling shows redraws are expensive — defer until needed.

**Rows:** SwiftUI `List` with `.listStyle(.plain)`, dividers disabled (we draw our own), selection bound to `$appState.selectedPRID`.

**Filter-change selection reconcile:**
- If `selectedPRID` is still present in the new filtered list → keep it
- Else if the new list is non-empty → set to `list.first.id`
- Else set to `nil` → empty detail state

### `MailRowView`

Per-row layout, 9pt × 14pt padding, `border-bottom: 0.5pt hairline`.

**Background priority:**
- Selected → `rowSelect`
- Hovered (not selected) → `rowHover`
- Otherwise transparent

**Read affordance:** When `pr.isUnread == false && !isSelected`, the whole row drops to `opacity: 0.62`.

**Priority rail:** Absolutely positioned 3×(height-12) bar at `leading: 0`, 6pt top/bottom inset, `border-radius: 2`. Color from the Roles palette for the row's bucket. When read, rail `opacity: 0.5`.

**Top line** (HStack, spacing 7, center alignment):
- `UnreadDot(on: pr.isUnread)` — 8pt circle, `unreadDot` color, soft 2pt ring (`unreadDot` × 0.22). When off → transparent.
- Title — 13pt, weight 700 if unread else 500, color `accentText` if selected else `text`, single line ellipsis, letter-spacing −0.05.
- Time — 10.5pt `textFaint`, tabular-nums, no wrap. Relative ("5m ago" via existing `RelativeTimeFormatter`).

**Second line** (HStack, spacing 6, 4pt top padding):
- 16pt `AvatarView`
- Author display name — 11.5pt 500 `textMuted`
- Middle dot · `#PR-number` (11pt tabular `textFaint`)
- Spacer
- Trailing: **MergedPill** if merged, else **MiniGaugeDots**

**Optional hint snippet** (controlled by build constant `showHints = true`):
- 5pt below second line, leading-aligned to 15pt (past the unread dot)
- 11.5pt `textMuted`, line-height 1.4, clamped to 2 lines
- Source: `pr.attentionHint ?? pr.mentionHint ?? pr.involvedHint`

**Context menu** (`.contextMenu`):
- "Mark as unread" (visible when read) → `setLastReadAt(date: nil)`
- "Mark as read" (visible when unread) → `setLastReadAt(date: .now)`

### `MiniGaugeDots` (new)

Three 7pt circles, 3pt gap. Order: Review → CI → Merge.
- Filled (no border) when stage has a state, colored by state: `approved`/`changes`/`pending`/`commented`.
- Outlined 1pt `borderStrong` when stage is empty.
- Pulsing animation on the running/pending dot.

Tooltip on hover (macOS `.help(...)` modifier) lists each stage's state in plain text.

### `UnreadDot` (new)

8pt circle, `unreadDot` token. When `on` → solid fill + soft 2pt ring (`unreadDot.opacity(0.22)`). When `off` → transparent (occupies the same space for layout stability).

### `AccountFooter`

22pt avatar + name 12/600 + `@login` 10.5pt `textMuted`. Settings gear at trailing edge → `onOpenSettings()`.

### `MailDetailPaneView` (rewrite of `PRDetailView`)

**Header** — `panelBg` background with same blur treatment as the source list, 10pt top / 18pt horizontal / 12pt bottom padding, `border-bottom: 0.5pt border`.

Top toolbar row:
- Breadcrumb: `repo-name` (11.5pt faint) · `/` (faint) · `#5107` (11.5pt muted tabular) · middle dot · status pill (Open / Merged / Closed / Draft) using the existing color logic.
- Spacer.
- "Updated 2m ago" stamp with clock icon (or "Refreshing…" with spinner), 11pt muted. Pulls from `coordinator.lastSyncAt`.
- "Open on GitHub" link (existing chrome).
- Refresh button: 24×24, `cardBg`, 0.5pt `border`, radius 5. Spins while `isLoading`.

**No back button.** **No theme toggle** (lives in Settings).

Title — 17pt 700 `text`, letter-spacing −0.2, multi-line allowed.

Metadata row — same content as today: avatar + author + "wants to merge into" + base-branch pill + "from" + head-branch pill + middle dot + "opened Xd ago".

**Body** — `HStack(spacing: 0)`:
- **TimelineColumn** (flex 1, padding 16 × 20 × 22) — fidelity pass:
  - 1pt vertical hairline rail at `leading: 13`
  - Each event: 20pt colored dot at `leading: 4` with a 2pt `contentBg` border (cutout effect)
  - Content offset right by 38pt
  - Seen events `opacity: 0.48`; new events full opacity with a 4pt accent bar at `leading: -4` and a 3pt `accent.opacity(0.22)` ring on the dot
  - Event types and dot colors per spec (`handoff-mail/README.md` §Detail body)
- **DetailRightRail** (width 232pt, `border-left: 0.5pt border`, padding 16pt, `background: panelBg`) — section order:
  1. **Status** — RailRow for Review / CI / Mergeable, each with compact pill
  2. **CI checks** — list of `{label, state, time}`
  3. **Reviewers** — avatar + name + ReviewPill compact per reviewer
  4. **Labels** — flex-wrap pills
  5. **Changes** — `+N` / `−N` / `· N files`
  6. **Mark as unread** — full-width secondary button → `setLastReadAt(date: nil)`

The current "Mark all seen" / "Mark all unseen" pair is replaced by the single "Mark as unread" button (PR-level). Per-event seen toggling remains accessible via the timeline (existing tap-to-toggle behavior).

**QuickReply** — kept as visual placeholder. Textarea is editable; "Comment" button is enabled when textarea non-empty (per spec) but submission stays stubbed. No GitHub API call yet.

**Empty state** — `MailEmptyDetailView`: VStack center, 28pt PR icon `textFaint × 0.5`, "No pull request selected." 13pt `textFaint`. 8pt spacing.

### `MailDetailPaneView.task(id: pr.id)` behavior

On detail-pane mount or PR change:
1. `await loadTimeline()` — existing behavior
2. `await syncActor.setSeenForPR(prID:isSeen: true)` — existing behavior; dims seen events
3. `await syncActor.setLastReadAt(prID:, date: .now)` — new; clears the unread dot

## 6. Tokens

`PRTracker/DesignSystem/Tokens.swift` currently defines a flat set of static `Color`s. Migrate to dynamic light/dark using SwiftUI's `Color(light:dark:)` initializer (macOS 15+ / iOS 18+).

**New token keys** (all need light + dark variants):

```
windowBg, panelBg, contentBg, sidebarBg
border, borderStrong, hairline
text, textMuted, textFaint
accent, accentBg, accentText
approved, approvedBg
changes, changesBg
pending, pendingBg
commented, commentedBg
cardBg, cardShadow
rowHover, rowSelect
unreadDot, newHighlight
```

Light + dark RGBA values are taken verbatim from `handoff-mail/README.md` §"Theme tokens".

**Lane palette ("Roles" default):**

```swift
enum LaneColors {
    static let review    = Color(hex: 0x0a84ff)
    static let attention = Color(hex: 0xff9500)
    static let mine      = Color(hex: 0x30b94d)
    static let involved  = Color(hex: 0x8e8e93)
    static let mentions  = Color(hex: 0xbf5af2)
    static let recent    = Color(hex: 0x8250df)
}
```

Other palette variants ("Saturated", "Muted", "Urgency") from the prototype are deferred — Roles ships as the only choice.

## 7. Behavior summary

| Action | Effect |
|---|---|
| Row tap | `selectedPRID = pr.id`; detail loads timeline; `setSeenForPR(isSeen: true)`; `setLastReadAt(.now)` |
| Row right-click → "Mark as unread" | `setLastReadAt(nil)` |
| Row right-click → "Mark as read" | `setLastReadAt(.now)` |
| Filter pill tap | `activeFilter = pill`; selection reconcile rule |
| Refresh button (detail header) | `coordinator.refresh()`; loadTimeline for current PR |
| Detail "Mark as unread" button | `setLastReadAt(nil)` |
| Theme change in Settings | Updates `ViewerState.themePreferenceRaw`; root view applies `preferredColorScheme` |

## 8. Settings, Onboarding, MenuBarExtra

### SettingsView

Add Theme picker (in existing "General" tab, or new "Appearance" tab — choose during implementation based on what reads cleaner):

- Picker with three options: System / Light / Dark
- Stored on `ViewerState` as `themePreferenceRaw: String` (default `"system"`)
- Read at the `MainView` root, applied via `.preferredColorScheme(...)` (nil for System, `.light`, or `.dark`)

Other Settings tabs (Account, Repos): token + typography pass only. No logic changes.

### OnboardingView

Token + typography pass. Card backgrounds use `cardBg` with 0.5pt `border`, primary buttons in `accent`, secondary in `cardBg`/border. Titles 13/700, body 11.5/500. No flow changes.

### MenuBarExtra (`MenuBarContentView`)

Compress the row anatomy for the smaller ~320pt-wide popover:
- Priority rail (3pt) on leading edge
- Single line: UnreadDot · Title (12/700 unread, 12/500 read) · Time
- No second line, no MiniGaugeDots, no hint snippet
- Same `rowSelect`/`rowHover` backgrounds
- Tap → opens main window with that PR selected (existing behavior)

Section headers (e.g. "Attention", "Review") — keep if currently present, restyle as 10.5/700 uppercase `textFaint` with 0.6 letter-spacing.

## 9. Removed code

To be deleted on the redesign branch:

- `PRTracker/Views/Feed/Sidebar.swift`
- `PRTracker/Views/Feed/FeedView.swift`
- `PRTracker/Views/Feed/FeedSection.swift`
- `PRTracker/Views/Feed/FeedToolbar.swift`
- `PRTracker/Views/Feed/PRCardView.swift`
- `PRTracker/Views/Feed/StatusGauge.swift` (or repurpose internals into `MiniGaugeDots` if useful)
- The slide-in transition in `MainView.body` (just shipped on `redesign`'s parent commit; removed in this rewrite)
- `PRDetailView`'s back-button block

The `Feed/` directory itself is removed since nothing else lives in it after the deletion. New mail-related views live under `PRTracker/Views/Mail/`.

`AppState.activeSection` and `enum Section` (the existing `Lane`/`Section` types in `Sync/Classifier.swift`) may stay if `Classifier.section(...)` is still the cleanest way to compute buckets internally — the bucket → filter mapping is 1:1. Confirm during implementation.

## 10. Testing

**Unit tests (added):**
- `MailFilterTests` — for each `MailFilter`, given a fixture of PRs, asserts the filtered list contains exactly the expected IDs.
- `PullRequestReadStateTests` — covers `isUnread` truth table: `lastReadAt == nil` → true; `updatedAt > lastReadAt` → true; `updatedAt <= lastReadAt` → false.
- `SelectionReconcileTests` — pure-function test of the rule: returns existing if in list, else `first.id`, else `nil`.

**Existing tests:**
- `ClassifierTests` — still applies; bucket logic unchanged.
- `SyncActorTests` — add a case for `setLastReadAt(prID:date:)`.
- `GitHubClientTests`, `KeychainTests`, etc. — unchanged.

**Manual smoke (cannot be automated in this repo):**
- Open the app signed in. Verify two-pane layout renders.
- Click each filter pill — count badge correct, list re-filters, selection reconciles.
- Open a PR — unread dot disappears on that row; row drops to 0.62 opacity.
- Right-click → "Mark as unread" — dot returns, opacity returns to 1.
- Empty filter — empty detail state shows.
- Switch theme in Settings — instant swap; no broken contrast.
- MenuBarExtra dropdown — restyled rows readable, tap opens detail.

## 11. Risks & open items

- **Hairline rendering on non-Retina displays** — 0.5pt strokes may render as 1pt or vanish. Mitigation: use `Divider()`-style backed views or explicit `frame(height: 1/UIScreen.main.scale)`. Test on an external monitor during implementation.
- **`List` selection + context menu interaction** — SwiftUI's `List` selection-binding and per-row `.contextMenu` should compose, but I haven't verified at this version of macOS. Fall back to a custom `LazyVStack` with tap gestures if needed.
- **Scroll performance with large PR sets** — `LazyVStack` inside `ScrollView` performs poorly on macOS in some configurations. Prefer `List`. Measure with a synthetic 500-PR fixture during the row-implementation phase.
- **Multi-repo selector** — explicitly deferred. The `RepoSelectorCard` is a tap-to-open-Settings stub for now.
- **Quick reply submission** — explicitly deferred. Textarea + button activation logic ships; the actual GitHub POST does not.

## 12. Out of scope

(Restating from `handoff-mail/README.md` §"Out of scope" — for clarity, none of these are part of this redesign.)

- File-diff view, inline-comment threads on diffs
- Multi-repo aggregation
- Notification center beyond MenuBarExtra
- Auth changes (existing OAuth flow stays)
- Lane palette variants beyond "Roles"
- Tweaks panel
