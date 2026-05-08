# Handoff: PR Tracker (macOS)

## Overview

A native **macOS application** that helps a developer stay on top of their GitHub pull requests for a single repository at a time. The main "feed" groups PRs into priority-driven sections (needs attention, needs review, mine, mentions, involved, recently merged). Drilling into any PR shows its conversation timeline, CI breakdown, reviewers, and labels, with a quick-reply area. The app supports local read/unread state (independent of GitHub), periodic auto-refresh and manual refresh, and both light and dark appearances. A menu-bar indicator provides at-a-glance counts without opening the main window.

## About the Design Files

The files bundled in `design/` are **design references created in HTML/React** — prototypes that demonstrate the intended look and behavior. They are **not production code to copy directly**. Your task is to **recreate these designs in the target application's environment** using its established patterns and libraries.

For a native macOS app this almost certainly means **SwiftUI** (or AppKit if the existing codebase requires it). For a cross-platform Electron-style app, use the repo's chosen React/Vue stack. The design values (colors, spacing, typography, component composition) translate directly; the *implementation* should be idiomatic to the target platform.

The HTML prototype is a design canvas (`PR Tracker.html`) that opens with several artboards: the primary app, gauge-style sub-variants, density sub-variants, color-system sub-variants, grouping/emphasis sub-variants, PR detail view, and menu-bar indicator preview. The **primary** artboard and the **bars** gauge style are the chosen defaults.

## Fidelity

**High-fidelity.** Exact colors, type sizes, weights, spacing, and interaction details are defined. Recreate pixel-perfectly in the target environment using its native controls where they exist (e.g. SwiftUI's `List`, `Menu`, `Picker`, SF Symbols for icons, `.regularMaterial` for translucency) rather than reproducing the CSS literally.

## Screens / Views

### 1. Main Window — Feed

A single macOS window, 1280×820 in the mock (should be resizable). Three regions:

- **Sidebar (width 220, translucent)** — traffic lights at top, repo switcher card, then the feed nav:
  - All feed (inbox icon)
  - Needs my attention (orange rail, pulsing dot when count > 0)
  - Needs my review (blue rail)
  - Mentions (purple rail)
  - My open PRs (green rail)
  - Others' PRs (gray rail)
  - Recently merged (purple rail)
  Each row shows a 4×14 colored rail, label, and a count pill. Selected row uses `accentBg`.
  Footer: current user avatar + name + @login + settings gear.

- **Toolbar (height 44, translucent)** — title + repo subtitle on the left. On the right: "Updated <relative time>" with clock icon (or spinner + "Refreshing…"), Refresh button, theme toggle (moon/sun).

- **Content area** — a scrollable column of collapsible sections. Each section has a chevron (collapsed rotates -90°), a 8×8 square tinted with the section's rail color, a title (fontSize 12.5, weight 700), and a count pill. Section body is a vertical stack of PR cards with `gapOuter` spacing.

When the grouping tweak is "Unified", sections disappear and PRs are one flat list sorted by `lastActivity` desc.

### 2. PR Card (Priority Lanes — the chosen layout)

Card: `cardBg` background, 0.5px `border`, border-radius 10, subtle `cardShadow`, hover border becomes `borderStrong`. Unread items are full opacity; read items render at **0.5 opacity** (the core "previously viewed dims" behavior). A vertical color rail on the left edge encodes priority:

- attention: #ff9500 (orange)
- review: #0a84ff (blue)
- mine: #30b94d (green)
- involved: #8e8e93 (gray)
- mentions: #bf5af2 (purple)
- recent: #8250df (violet)

Rail width: 3 (compact) / 4 (comfortable, default) / 5 (spacious) px.

**Top row:** unread dot (8×8, theme accent with glow when on) · PR number (#5107, textMuted, tabular numerals) · title (fontSize 13.5, weight 600 if unread, 500 if read) · relative time (right-aligned, 10.5px, textFaint).

**Meta row (not shown when density=compact):** author avatar (18px comfortable, 20 spacious) · author name (text, 11.5, weight 500) · dot separator · branch name in ui-monospace (10.5px, textFaint, max-width 280) · flexspace · gauge.

**Hint bubble:** if the PR has an attentionHint / mentionHint / involvedHint, render a 6px-radius rounded block below the meta row, background `newHighlight` (accent at 6–8% alpha), fontSize 11.5, text color `text`.

### 3. Status Gauge (Bars — the chosen style)

Three stacked "stages": Review → CI → Merge. Rendered as three small horizontal bars, each 34×4 px with 6px gap:

- ok → filled `approved` green
- bad → filled `changes` red
- running → filled `pending` yellow with a shimmer animation sweeping left-to-right (1.4s linear infinite)
- inactive → `hairline` gray

Below each bar, a 9.5px uppercase label (Review / CI / Merge) in the bar's color when active, or textFaint when inactive. Letter-spacing 0.2.

Alternate gauge styles (pills, dots) are available and should be easy to swap via a parameter.

### 4. PR Detail View

Opened by clicking a card. Replaces the feed area.

**Header (24px padding, panelBg with bottom border):**
- Back button ("◀ Feed"), "spark-ios / #5107", Open pill on right.
- Title (fontSize 18, weight 700, letter-spacing -0.2, text-wrap: pretty).
- Meta line: author avatar + name + "wants to merge into" + `main` (monospace, hairline bg) + "from" + branch (monospace, hairline bg) + "opened 2d ago".

**Body — two columns:**

Left (flex:1, 18–24px padding, scrolls):
- **Timeline** with a 1px vertical rail at left=13. Each event has a 20×20 circular dot at left=4 with a 2px `contentBg` border (floats on the rail). Dot color by type:
  - commit: textMuted (light gray, commit icon)
  - review APPROVED: approved green (checkmark)
  - review CHANGES_REQUESTED: changes red (x)
  - review COMMENTED: commented gray (speech bubble)
  - comment: accent blue (speech bubble)
  - status: pending yellow (spinner)
  - opened: approved green (pr icon)
- **Seen events render at 0.48 opacity**; new events (isNew=true) have a 4×28 vertical accent bar at left=-4 and a `accent@22` glow ring on their dot. Comment/review bodies are rendered as cards (cardBg, 0.5 border, 8px radius, 10/12 padding). Non-card events are inline rows with avatar + verb text + optional SHA pill.
- **Quick reply block:** cardBg panel with user avatar + "Reply as <name>", textarea (100% width, min-height 70, 6px radius, 13px), and three buttons at bottom-right: Approve (secondary), Request changes (secondary), Comment (primary, `accent` fill, disabled when empty).

Right rail (width 260, 18px padding, panelBg, left border):
- **Status** section: Review / CI / Mergeable each shown as `RailRow` with compact pill on right.
- **CI checks** section: per-check rows with icon + name + time. Check icons: green check, red x, yellow spinner, gray dot.
- **Reviewers** section: avatar + name + compact review pill.
- **Labels** section: pill chips (10.5px, hairline bg, textMuted, 999 radius).
- **Changes** section: "+142 −38 · 7 files" with green/red colors.
- **"Mark all as unread"** button (full-width secondary).

### 5. Menu-Bar Indicator

Not a window — a macOS menu-bar status item. Renders the PR icon (same as the sidebar icon, 16px) with a **red circular badge** (13×13 min, 9px white bold text, 1.5px menu-bar-colored ring) when attention count > 0. Clicking opens a standard macOS dropdown (width ~320):

- Header row: repo name (bold) · "Updated just now" (muted)
- Section rows: colored dot/icon · label · count on right. Blue highlight on hover (NSMenuItem style).
  - Needs my attention (orange dot)
  - Needs my review (blue eye)
  - My open PRs (green PR icon)
  - Mentions (purple @)
- Divider
- Highlight row: "#5107 Fetch badge data…" with sub-line "Iris: 'Testing on device now!'" in italic muted.
- Divider
- Open PR Tracker / Refresh now (⌘R) / Preferences… (⌘,)
- Divider
- Quit (⌘Q)

## Interactions & Behavior

- **Click PR card** → opens detail view. Auto-marks the PR as read on open.
- **Right-click PR card** → toggles read/unread (no system context menu in this design; hijack the contextmenu event or show a single-item menu).
- **Hover PR card** → reveals a small "mark read/unread" eye button (opacity 0→1, 150ms). On native macOS, this can be a hover-revealed `Image(systemName: "eye")` button.
- **Keyboard** (to add in native impl — not in prototype): J/K to move focus between cards, U to toggle unread, R to refresh, ⌘← to close detail.
- **Collapsible sections**: click the section header to toggle. Chevron rotates between 0° and -90° (150ms).
- **Refresh**: `Refresh` button triggers a fetch. Show spinner + "Refreshing…" while in flight. Update "Updated <relative>" on success. Additionally run an auto-refresh on a configurable interval (default 2 minutes when window is visible; pause when app is backgrounded beyond 10 min).
- **Local read/unread**: managed entirely in the app (no GitHub mutation). Persist to disk (UserDefaults / a small SQLite keyed by `(repo, prNumber)` is fine). Two pieces of state: per-PR `isRead`, and per-timeline-event `hasSeen` for the detail view.
- **Timeline "seen" behavior**: when a user opens a detail view, any events older than the last-visit timestamp for that PR are marked "seen" (rendered at 0.48 opacity). New events keep full opacity and the blue accent until visited. The right-rail "Mark all as unread" clears the per-PR last-visit, causing the card to become bold again and all events to lose their "seen" state.
- **Theme toggle**: flips between light and dark tokens. Should also honor system appearance by default.
- **Tweaks panel** (dev-time only; production would be Settings): floating panel in the prototype exposing gaugeStyle, density, palette, grouping, statusEmphasis, authorPlacement. In the shipping app, collapse these to a single **Settings** screen: gauge style and density are reasonable user prefs; palette/grouping are optional power-user prefs; others can be constants.

## State Management

Per `(repo, user)`:
- `pullRequests: [PR]` — the most recent fetch
- `lastFetchedAt: Date`
- `isFetching: Bool`

Per `(repo, prNumber)`:
- `lastVisitedAt: Date?` — for seen/unseen calculation
- `manualUnread: Bool` — overrides "seen" when user toggles

Global:
- `appearance: system | light | dark`
- `refreshIntervalMinutes: Int` (default 2)
- `activeRepoId: String`
- `activeSectionId: String | nil` (nil = All)

## Design Tokens

### Colors — Light theme
| Token | Hex |
|---|---|
| windowBg | #ffffff |
| panelBg | rgba(246,246,248,0.85) |
| contentBg | #ffffff |
| sidebarBg | rgba(210,225,245,0.45) |
| border | rgba(0,0,0,0.08) |
| borderStrong | rgba(0,0,0,0.14) |
| hairline | rgba(0,0,0,0.06) |
| text | rgba(0,0,0,0.88) |
| textMuted | rgba(0,0,0,0.56) |
| textFaint | rgba(0,0,0,0.38) |
| accent | #007aff |
| accentBg | rgba(0,122,255,0.10) |
| accentText | #0062cc |
| approved | #1a7f37 · approvedBg rgba(26,127,55,0.10) |
| changes | #cf222e · changesBg rgba(207,34,46,0.10) |
| pending | #9a6700 · pendingBg rgba(154,103,0,0.10) |
| commented | #6e7781 · commentedBg rgba(110,119,129,0.10) |
| cardBg | #ffffff |
| cardShadow | 0 1px 2px rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.05) |
| rowHover | rgba(0,0,0,0.03) |
| rowSelect | rgba(0,122,255,0.10) |
| unreadDot | #007aff |
| newHighlight | rgba(0,122,255,0.06) |

### Colors — Dark theme
| Token | Hex |
|---|---|
| windowBg | #1c1c1e |
| panelBg | rgba(28,28,30,0.85) |
| sidebarBg | rgba(44,44,46,0.55) |
| border | rgba(255,255,255,0.10) |
| text | rgba(255,255,255,0.92) |
| textMuted | rgba(235,235,245,0.60) |
| textFaint | rgba(235,235,245,0.40) |
| accent | #0a84ff |
| approved | #3fb950 |
| changes | #f85149 |
| pending | #d29922 |
| commented | #8b949e |
| cardBg | #2c2c2e |
| unreadDot | #0a84ff |

### Lane / Priority colors (role-based)
- attention #ff9500 · review #0a84ff · mine #30b94d · involved #8e8e93 · mentions #bf5af2 · recent #8250df
- Alternate palettes provided: `saturated`, `muted` (all gray), `semantic` (red/yellow/green urgency only). The shipping default is role-based (above).

### Typography
- Font: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro"` (i.e. **SF Pro** on macOS — use the system font).
- Monospace: `ui-monospace, SFMono-Regular, Menlo` (for branch names and SHA).
- Sizes: window title 14, section header 12.5, card title 13.5, meta 11.5, micro 10.5, numerals 11–12 tabular.
- Card title weight: 600 if unread, 500 if read.
- Detail title: 18 / 700 / letter-spacing -0.2 / text-wrap: pretty.

### Spacing
- Density presets (padY / padX / inner gap / outer gap / rail width):
  - compact: 7 / 12 / 6 / 4 / 3
  - comfortable (default): 11 / 14 / 8 / 7 / 4
  - spacious: 14 / 16 / 10 / 10 / 5
- Sidebar width 220. Toolbar height 44. Right-rail width 260. Card radius 10.

### Shadows
- Window: `0 0 0 0.5px rgba(0,0,0,0.18), 0 24px 70px rgba(0,0,0,0.35)`
- Card: `0 1px 2px rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.05)` (light); dark uses 0.3/0.35 alphas
- Dropdown (menu-bar): `0 16px 40px rgba(0,0,0,0.28), 0 2px 8px rgba(0,0,0,0.1)`

### Animations
- Hover transitions: 120–180ms cubic-bezier default.
- Shimmer (running CI bar): translateX(-100% → 100%) 1.4s linear infinite.
- Pulse (attention dot): opacity 1 → 0.5 → 1 over 1.6s ease-in-out infinite.
- Chevron rotate: 150ms.

## Assets

No bitmap assets required. Icons are inline SVG in the prototype; on macOS, **use SF Symbols**:
- `arrow.triangle.pull` (pull request), `arrow.triangle.merge` (merged)
- `checkmark`, `xmark`, `clock`, `arrow.clockwise` (refresh)
- `eye` / `eye.slash` (mark read/unread)
- `at`, `tray`, `gearshape`
- `moon` / `sun.max` (theme toggle)
- `chevron.right`, `chevron.left`, `chevron.down`

User avatars are colored-initials placeholders in the mock. In production, fetch GitHub's avatar URLs and cache locally.

## Files

All design files are in `design/`. The canvas index is `PR Tracker.html`. Key components:
- `data.jsx` — the mock data model; use as a schema reference for the PR / timeline event shapes.
- `ui-primitives.jsx` — themes, avatar, review/CI/mergeable pills, icon set.
- `mac-shell.jsx` — window frame, sidebar, toolbar (generic, shared with earlier variants).
- `feed-lanes.jsx` — the chosen feed (priority rail + gauge), density/palette/gauge-style logic.
- `pr-detail.jsx` — detail view with timeline, CI breakdown, reviewers, labels, quick reply.
- `tweaks-menubar.jsx` — Tweaks panel + menu-bar dropdown preview.
- `pr-app-c.jsx` — top-level app that wires it all up (the **default** option values are at the top of this file).
- `design-canvas.jsx` — presentation scaffold (not part of the shipping app).

### Default option values (from `pr-app-c.jsx`)
```json
{
  "gaugeStyle": "bar",
  "density": "comfortable",
  "palette": "current",
  "grouping": "sections",
  "statusEmphasis": "always",
  "authorPlacement": "meta"
}
```

## GitHub integration notes (for the implementer)

- Use the GraphQL v4 API for the feed — a single query per repo can fetch all PRs with reviews, check runs, labels, and the latest comment. Fields the mock relies on:
  - `number, title, author, headRefName, baseRefName, state, isDraft, additions, deletions, changedFiles, createdAt, updatedAt, mergedAt, mergeable`
  - `reviews(last:50) { author, state, submittedAt }`
  - `commits(last:1) { statusCheckRollup { state, contexts { … } } }` for the CI breakdown
  - `timelineItems(first:100) { … }` for the detail timeline
- Section classification (done client-side):
  - **needsMyReview**: I'm a requested reviewer and have not yet reviewed.
  - **needsMyAttention**: I'm the author *and* a reviewer requested changes OR CI failed OR there's an unread comment from a reviewer.
  - **mine**: `author == me && state == OPEN`.
  - **involved**: I've reviewed or commented, author ≠ me, state == OPEN.
  - **mentions**: any comment body contains `@me` that we haven't surfaced yet.
  - **recent**: `state == MERGED && mergedAt > now - 7d`.
- Auto-refresh: suggest 2 min foreground, 10 min background. Use ETag caching to keep bandwidth low.
- Notifications: request `UNUserNotificationCenter` auth and surface a local notification when a PR enters "needs my attention" since the last poll.

## Out of scope for this handoff
- Settings screen (described at a high level above; detailed design to follow if needed)
- Onboarding / sign-in flow
- Multi-repo unified feed (the design is single-repo; switcher is in the sidebar)
- Notifications UI beyond system notification posting
