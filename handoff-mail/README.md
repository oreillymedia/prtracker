# Handoff: PR Tracker — Mail-style two-pane layout

## Overview

A macOS desktop app for tracking GitHub Pull Requests, designed around the **two-pane mail-app pattern**: a filterable source list on the left, a permanent PR detail view on the right. No drilling: selecting a row in the list swaps what's shown in the detail pane — exactly like Mail.app, Things, or Linear's triage view.

The product audience is engineers (the persona "Alex Chen") who get drowned in PR notifications and want a single, calm place to scan everything that needs them. The app's job is to surface "what needs me right now" first, then everything else.

## About the design files

The files in this bundle are **design references created in HTML** — interactive prototypes that show the intended look, layout, and behavior. They are NOT production code to copy directly.

The HTML uses inline React + Babel for prototyping speed; in a real codebase you should **recreate the design in the target app's existing environment** (e.g. SwiftUI for a real Mac app, Electron + React, a native AppKit app, etc.) using its established patterns. If no environment exists yet, SwiftUI is the natural choice for a Mac-only menubar/desktop app; Electron + React is appropriate if cross-platform is required.

## Fidelity

**High-fidelity.** Spacing, type, color, and component states are intentional and should be matched closely. Where the spec gives a pixel value, treat it as the target; where it describes a behavior (e.g. "fades to 0.62 opacity when read"), match the visual effect.

## Files in this bundle

| File | Role |
|---|---|
| `PR Tracker.html` | Entry HTML. Loads scripts and renders a design-canvas of variants. The **mail layout** is the first/primary section. |
| `pr-mail.jsx` | **The mail-style variant — the main deliverable.** Source list + filter pills + permanent detail pane. |
| `pr-app-c.jsx` | Earlier "Priority Lanes" feed variant. Included for reference; not the target design. |
| `pr-detail.jsx` | Detail-pane internals: timeline, CI breakdown, reviewers rail, quick reply, status pills. Used by both variants. |
| `feed-lanes.jsx` | Gauge components (`Gauge`, `GaugePills`, `GaugeBar`, `GaugeDots`), `computeStages`, `LANE_COLORS` palette tokens, `priorityFor` helper. The mail variant uses `computeStages` and `LANE_COLORS`. |
| `ui-primitives.jsx` | Theme tokens (`THEMES.light`, `THEMES.dark`), `Avatar`, `AvatarStack`, icons (`I`), `ReviewPill`, `CIPill`, `MergeablePill`, `UnreadDot`. Source of truth for colors. |
| `mac-shell.jsx` | `MacShell` window chrome (traffic lights, drop shadow). |
| `data.jsx` | Mock data: `PULL_REQUESTS`, `USERS`, `ME`, `REPOS`, `TIMELINE_5107`, `relTime` helper. Use as a reference for the data shape your real GitHub adapter must produce. |
| `design-canvas.jsx` | Prototype-only artboard host. Not part of the product. |

The other variant files (`pr-app.jsx`, `feed-cards.jsx`, `feed-list.jsx`, `tweaks-menubar.jsx`, `app-icons.jsx`) are earlier explorations and can be ignored.

## Layout: mail-style two-pane

Window is **1280 × 820** in the prototype, but the app should be **resizable**. Two columns, no top toolbar:

```
┌──────────────────────────┬──────────────────────────────────────────┐
│  Source list (380px)     │  Detail pane (flex)                      │
│  ────────────────────    │  ──────────────                          │
│  • Traffic lights        │  • Detail header                         │
│  • Repo selector         │    – breadcrumb (repo / #num / status)   │
│  • Filter pills strip    │    – refresh + theme buttons             │
│  • Source list (scroll)  │    – title (17px bold)                   │
│  • Account footer        │    – author/branch metadata              │
│                          │  • Body: timeline | meta rail (232px)    │
│                          │    – timeline w/ comments + commits      │
│                          │    – quick reply box                     │
│                          │    – rail: Status / CI / Reviewers /     │
│                          │      Labels / Changes / Mark unread      │
└──────────────────────────┴──────────────────────────────────────────┘
```

### Left pane — Source list (width: 380px, fixed)

Glassy background (`rgba(210,225,245,0.45)` light, `rgba(44,44,46,0.55)` dark) with backdrop-filter blur(40px) saturate(180%). `border-right: 0.5px solid` theme border.

**Stacking order, top to bottom:**

1. **Traffic-lights row** — 38px tall, 12px gutter. Red `#ff5f57`, yellow `#febc2e`, green `#28c840`, 12×12 circles with 0.5px black 15% stroke.

2. **Repo selector** — 8px below traffic lights, 12px horizontal padding. A pressable card:
   - Background `cardBg`, `0.5px solid border`, `border-radius: 7px`, `padding: 6px 10px`
   - Left: 22×22 rounded-5 tile, linear-gradient `135deg, #c96442, #7b2d1a`, white "SP" 10px 700
   - Middle: org name (11px muted) over repo name (13px 600 `text`)
   - Right: chevron-down (10px, faint)

3. **Filter pills strip** — 8px top / 10px bottom padding, 12px horizontal, 6px gap between pills. `border-bottom: 0.5px solid hairline`. Horizontally scrollable (`overflow-x: auto`, `scrollbar-width: none`).
   - Filters in order: **All, Attention, Review, Mentions, Mine, Involved, Merged**
   - Pill chrome: `border-radius: 999px`, `padding: 4px 9px 4px 8px`, `font: 11.5px 600`, `0.5px solid border` (inactive) or transparent (active)
   - Inactive: `background: cardBg`, `color: text`. Active: `background: text`, `color: contentBg` (inverts to a near-black pill in light, near-white in dark)
   - 7px dot left of label colored by lane (see Palette below). The "All" pill has no dot.
   - Count badge right of label: 10px 700, muted color. Hidden when count is 0.

4. **List** (flex: 1, scrollable) — see "Source-list row" below.

5. **Account footer** — `border-top: 0.5px solid border`, `padding: 10px 14px`, 8px gap. Avatar (22px) + name (12px 600) over @login (10.5px muted), settings icon on the right.

#### Source-list row

`padding: 9px 12px 9px 14px`, `border-bottom: 0.5px solid hairline`.

**Backgrounds (priority order):**
- Selected: `rowSelect` (`rgba(0,122,255,0.10)` light / `rgba(10,132,255,0.20)` dark)
- Hovered (not selected): `rowHover` (`rgba(0,0,0,0.03)` / `rgba(255,255,255,0.04)`)
- Otherwise: transparent

**When the row is "read" but not selected, the whole row drops to `opacity: 0.62`.** This is the most important affordance — unread items stand out without any badge.

**Priority rail** — absolutely positioned, `left: 0`, `top: 6, bottom: 6`, `width: 3`, `border-radius: 2`. Color from the lane palette for the row's bucket (see Palette). When read, rail `opacity: 0.5`.

**Top line** (display: flex, align: center, gap: 7):
- 8×8 unread dot — solid `unreadDot` color (`#007aff`/`#0a84ff`) with a soft 2px ring `unreadDot22` when on, transparent when read.
- Title — `font: 13px / weight 700 if unread else 500`, `color: accentText if selected else text`, single line truncate with ellipsis, `letter-spacing: -0.05`.
- Time stamp — 10.5px `textFaint`, tabular-nums, whitespace nowrap. Relative ("5m ago", "2h ago", "3d ago").

**Second line** (4px above the first, gap: 6):
- 16px avatar (initials on tinted fill, see Avatar in ui-primitives)
- Author display name — 11.5px 500 `textMuted`
- Middle dot · #PR-number (11px tabular `textFaint`)
- Spacer (flex: 1)
- Right side: either **Merged** pill (10.5px 600 #8250df with merge-icon, 3px gap) OR a **MiniGaugeDots** trio.

**MiniGaugeDots** — Three 7×7 circles, gap 3px, no border when filled, 1px `borderStrong` border when empty. Colors: `approved` (passed), `changes` (bad), `pending` (running, with `pr-pulse` 1.6s ease-in-out). Order: Review → CI → Merge. Hover tooltip lists each stage's state.

**Optional preview snippet** (controlled by tweak `showHints`):
- 5px below the second line, `margin-left: 15px` (aligned past the unread dot)
- 11.5px `textMuted`, line-height 1.4, clamped to 2 lines (`-webkit-line-clamp: 2`)
- Source: `pr.attentionHint || pr.mentionHint || pr.involvedHint`

**Empty state** — When the filter has no items, the list area shows: centered 40px-padded text, 12.5px italic `textFaint`: "Nothing in this filter."

### Right pane — Detail (flex: 1)

Background `contentBg` (`#ffffff` / `#1c1c1e`).

#### Detail header (10px top padding, 18px horizontal, 12px bottom, `border-bottom: 0.5px solid border`, `background: panelBg` with same blur as the source list)

**Toolbar row** (8px gap, 10px below: title):
- Breadcrumb text: "spark-ios" (11.5px faint) · "/" (faint) · "#5107" (11.5px muted tabular)
- Middle dot · status pill: Open (approved green/bg) with pr-icon, or Merged (#8250df with 12% tinted bg) with merge-icon. Pill is 10.5px 600, padding 1px 7px, radius 999.
- Spacer
- "Updated 2m ago" 11px muted with 11px clock icon (or "Refreshing…" with spinner)
- 24×24 refresh button: `cardBg`, `0.5px border`, radius 5, spins while `isRefreshing`.
- 24×24 theme toggle: same chrome, sun/moon icon.

**Title** — 17px 700 `text`, `letter-spacing: -0.2`, `text-wrap: pretty`, line-height 1.25, margin 0.

**Metadata row** (8px below title, 8px gap, flex-wrap):
- 18px avatar + author name (11.5px 500 `text`)
- "wants to merge into" (11.5px muted)
- Base branch in a `hairline`-background pill: monospace 10.5px, padding 1px 5px, radius 4
- "from"
- Head branch in the same pill style
- Middle dot · "opened 2d ago"

#### Detail body (flex: 1, display: flex, overflow: hidden)

Two columns. **No close button** — the detail pane is permanent.

**Left: timeline column** (flex: 1, padding 16px 20px 22px, overflow auto)

Vertical 1px hairline rail at `left: 13px` from top to bottom.

Each event = a 20×20 colored dot at `left: 4` with a 2px `contentBg` border (creates the cutout-from-rail effect), and content offset to the right by `padding-left: 38`. **Seen events: `opacity: 0.48`**; new events: full opacity with a 4px-wide accent-color bar at `left: -4` and a `0 0 0 3px accent22` ring on the dot.

Event types and their dot color/glyph:
- **commit** — `textMuted` background, commit glyph 11px white. Body: actor name + "pushed" + title + monospace 7-char sha pill (10.5px, `hairline` bg, padding 1px 5px, radius 3).
- **review** — colored by review state: APPROVED → `approved` green dot, check glyph; CHANGES_REQUESTED → `changes` red, x; COMMENTED → `commented` gray, comment glyph. Body is a card: `cardBg`, `0.5px border`, radius 8, padding 10px 12px. Top row: 20px avatar + author 12px 600 + ReviewPill compact + time 10.5px faint. Comment body: 13px 1.5 line-height.
- **comment** — `accent` blue dot, comment glyph. Same card as review minus the pill.
- **status** — `pending` amber dot, spinner glyph. Body is a single-line "{title}" 12.5px with optional bulleted details list (11.5px muted, line-height 1.55, padding-left 26).
- **opened** — `approved` green dot, pr glyph. Body: "{actor} opened this pull request".

For PRs without a hand-written timeline, render a stub: opened event → one review per non-pending reviewer → (if merged) a merge status event → grayed "Older activity…" footer (11.5px italic faint, margin-left 38).

**Quick reply** (18px below the last event):
- `cardBg`, `0.5px border`, radius 10, padding 12.
- Header: 20px avatar + "Reply as {me.name}" 12px 600
- `textarea`: 100% wide, min-height 64, padding 10, radius 6, `0.5px border`, `contentBg`, 13px inherit font, resize vertical, no outline.
- Button row right-aligned, gap 6:
  - **Approve** — secondary
  - **Request changes** — secondary
  - **Comment** — primary `accent`, disabled until textarea has content

**Right: meta rail** (width 232, flex-shrink 0, `border-left: 0.5px solid border`, padding 16px, overflow auto, `background: panelBg`)

Sections in order, each with a 10.5px 700 uppercase `textFaint` label (`letter-spacing: 0.6`, 8px below):

1. **Status** — three RailRows (label left muted 12px, value right):
   - Review → ReviewPill compact
   - CI → CIPill compact
   - Mergeable → MergeablePill compact
2. **CI checks** — list of `{label, state, time}` rows, 4px gap. Pass = check-glyph 11px green; fail = x 11px red; running = spinner amber. Time tabular faint 10.5px right-aligned.
3. **Reviewers** — 20px avatar + name (flex: 1, ellipsis) + ReviewPill compact, per reviewer.
4. **Labels** — flex-wrap pills, gap 4, padding 2px 7px, radius 999, `hairline` bg, 10.5px 500 muted.
5. **Changes** — single 12px row: +N green, −N red, ·, "N files" muted.
6. **Mark as unread** — full-width secondary button.

#### Empty detail state

When no PR is selected (only possible if a filter is empty), center the pane: 28px pr-icon at `textFaint` 0.5 opacity, "No pull request selected." 13px `textFaint`, 8px gap column.

## Filter pills behavior

```
filter      includes                                       sort
─────────   ────────────────────────────────────────────   ────────────────
All         every PR (deduped)                             lastActivity desc
Attention   pr.needsMyAttention === true                   default
Review      pr.needsMyReview === true                      default
Mentions    pr.mention === true                            default
Mine        pr.mine === true && pr.state === 'OPEN'        default
Involved    pr.involved === true                           default
Merged      pr.state === 'MERGED'                          default
```

Pill counts show the size of each bucket. The active pill is fully inverted (dark bg, light text in light mode).

When the filter changes:
- If the previously selected PR is still in the filter, keep it selected.
- Otherwise, select the first PR in the new list.
- If the new list is empty, show the empty state in the detail pane.

When a row is opened: mark it read locally (`readMap[id] = true`). Right-click a row to toggle read/unread.

## Palette — lane colors

The priority-rail color and filter-pill dot are both driven by the row's "bucket". The bucket of a PR is determined in priority order:

```
needsMyAttention   → 'attention'   (orange / red in semantic)
needsMyReview      → 'review'      (blue / amber)
mention            → 'mentions'    (purple / amber)
mine && OPEN       → 'mine'        (green)
involved           → 'involved'    (gray)
state==='MERGED'   → 'recent'      (purple)
otherwise          → 'all'
```

Default palette ("Roles"):

| bucket | hex |
|---|---|
| review    | #0a84ff |
| attention | #ff9500 |
| mine      | #30b94d |
| involved  | #8e8e93 |
| mentions  | #bf5af2 |
| recent    | #8250df |

Three alternates are wired through the Tweaks panel (Saturated, Muted, Urgency); see `LANE_COLORS` in `feed-lanes.jsx`. **Ship "Roles" as the default**; the others are exploration variants.

## Theme tokens

From `ui-primitives.jsx`. The whole UI references these tokens via a `ThemeCtx` provider so light/dark swaps instantly.

### Light
```
windowBg     #ffffff
panelBg      rgba(246,246,248,0.85)
contentBg    #ffffff
sidebarBg    rgba(210,225,245,0.45)
border       rgba(0,0,0,0.08)
borderStrong rgba(0,0,0,0.14)
hairline     rgba(0,0,0,0.06)
text         rgba(0,0,0,0.88)
textMuted    rgba(0,0,0,0.56)
textFaint    rgba(0,0,0,0.38)
accent       #007aff
accentBg     rgba(0,122,255,0.10)
accentText   #0062cc
approved     #1a7f37    approvedBg rgba(26,127,55,0.10)
changes      #cf222e    changesBg  rgba(207,34,46,0.10)
pending      #9a6700    pendingBg  rgba(154,103,0,0.10)
commented    #6e7781    commentedBg rgba(110,119,129,0.10)
cardBg       #ffffff    cardShadow 0 1px 2px rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.05)
rowHover     rgba(0,0,0,0.03)
rowSelect    rgba(0,122,255,0.10)
unreadDot    #007aff
newHighlight rgba(0,122,255,0.06)
```

### Dark
```
windowBg     #1c1c1e
panelBg      rgba(28,28,30,0.85)
contentBg    #1c1c1e
sidebarBg    rgba(44,44,46,0.55)
border       rgba(255,255,255,0.10)
borderStrong rgba(255,255,255,0.18)
hairline     rgba(255,255,255,0.06)
text         rgba(255,255,255,0.92)
textMuted    rgba(235,235,245,0.60)
textFaint    rgba(235,235,245,0.40)
accent       #0a84ff
accentBg     rgba(10,132,255,0.18)
accentText   #64a9ff
approved     #3fb950    approvedBg rgba(63,185,80,0.15)
changes      #f85149    changesBg  rgba(248,81,73,0.15)
pending      #d29922    pendingBg  rgba(210,153,34,0.15)
commented    #8b949e    commentedBg rgba(139,148,158,0.15)
cardBg       #2c2c2e
rowHover     rgba(255,255,255,0.04)
rowSelect    rgba(10,132,255,0.20)
unreadDot    #0a84ff
newHighlight rgba(10,132,255,0.08)
```

## Typography

System font stack: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro", "Helvetica Neue", sans-serif` with antialiased smoothing. **Do not introduce a custom typeface.**

| Use | Size | Weight | Letter-spacing | Notes |
|---|---|---|---|---|
| Detail title | 17 | 700 | −0.2 | text-wrap: pretty, line-height 1.25 |
| List row title (unread) | 13 | 700 | −0.05 | single line, ellipsis |
| List row title (read) | 13 | 500 | −0.05 | |
| List row metadata | 11.5 | 500 | 0 | author name |
| List #-number | 11 | 400 | 0 | tabular-nums |
| List time | 10.5 | 400 | 0 | tabular-nums, faint |
| Repo name | 13 | 600 | 0 | |
| Repo org | 11 | 400 | 0 | muted |
| Section label (rail) | 10.5 | 700 | 0.6 | uppercase, faint |
| Filter pill label | 11.5 | 600 | 0 | |
| Body text (timeline comment) | 13 | 400 | 0 | line-height 1.5, text-wrap: pretty |
| Metadata copy ("wants to merge into") | 11.5 | 400 | 0 | muted |
| Monospace branch / sha | 10.5 | 400 | 0 | ui-monospace, SFMono-Regular, Menlo |

## Spacing & radii

- Window radius: 12
- Source list width: **380**
- Meta rail width: **232**
- Row vertical padding: **9** (top) / **9** (bottom). Horizontal: 12 / 14.
- Card radius (timeline comment, quick reply): 10
- Pill radius: 999
- Button radius: 5–6
- Avatar diameter scale: 16 / 18 / 20 / 22
- Standard hairline: `0.5px solid border`

## Avatars

Initials (first two name parts) on a saturated color fill (per-user, see `USERS` in `data.jsx`). Letter color white. Font size ≈ `size * 0.42`, weight 600, letter-spacing 0.2. Border-radius 50%. Optional 2px ring (`box-shadow: 0 0 0 2px var(--avatar-ring, #fff)`) for stacks.

## Pills (review / CI / merge)

All compact pills: `padding: 1px 6px 1px 5px`, `border-radius: 999`, `font: 10.5px 600`, icon at 10–11px, 4px gap.

- **ReviewPill** — solid tinted background. APPROVED/CHANGES_REQUESTED/PENDING/COMMENTED map to the four theme color pairs.
- **CIPill** — outlined (`background: transparent`, `border: 1px solid color33`). Picks dominant state: fail > running > pass.
- **MergeablePill** — text only, no background. Tiny 7px dot prefix.

## Interactions & behavior

- **Row click** → select PR, mark it read, swap the detail pane. No animation needed beyond the row background highlight.
- **Row right-click** OR **"Mark as unread" button in detail rail** → toggle read state for that PR id.
- **Filter pill click** → swap the active filter. List re-filters instantly; selection follows the rule above.
- **Refresh button (detail header)** → spin the icon for 900ms, update "Updated 2m ago" → "Updated just now".
- **Theme toggle** → swap `THEMES.light` ↔ `THEMES.dark`. No transition; instant swap (matches native macOS appearance switch).
- **Quick-reply Comment button** → disabled until `textarea` non-empty; otherwise primary blue.
- **Spinner** uses CSS `@keyframes pr-spin { to { transform: rotate(360deg); } }` at 1s linear infinite (1.1s for tiny variant).
- **Pulse** for the unread/running dots: `@keyframes pr-pulse { 0%,100% { opacity: 1 } 50% { opacity: 0.5 } }` 1.6s ease-in-out infinite.
- **Hovered row gauge** is full-color, not dimmed (the read-state `0.62` opacity does not apply to the colored rail's bottom layer — only the rest of the row).

## State

```ts
type AppState = {
  theme: 'light' | 'dark'
  activeFilter: 'all' | 'attention' | 'review' | 'mentions' | 'mine' | 'involved' | 'recent'
  selectedId: number | null
  readMap: Record<number, boolean>  // overrides PR.unread per-id
  isRefreshing: boolean
  lastUpdated: string  // human-readable
  opts: {
    palette: 'current' | 'saturated' | 'muted' | 'semantic'
    showGauge: boolean   // mini gauge dots in list rows
    showHints: boolean   // preview snippet line in list rows
  }
}
```

Selection auto-reconciles when `activeFilter` changes (see "Filter pills behavior").

## Data shape

The shape of a PR (see `PULL_REQUESTS` in `data.jsx`) — your GitHub adapter must map onto this:

```ts
type PR = {
  id: number
  number: number
  title: string
  author: string          // login key into USERS
  repo: string            // 'spark-ios'
  branch: string          // head branch
  base: string            // base branch
  state: 'OPEN' | 'MERGED' | 'CLOSED'
  isDraft: boolean

  // Bucket flags (computed server-side or by adapter)
  mine: boolean
  needsMyReview?: boolean
  needsMyAttention?: boolean
  involved?: boolean
  mention?: boolean

  // Review state — your review on this PR (or aggregate)
  review: 'APPROVED' | 'CHANGES_REQUESTED' | 'PENDING' | 'COMMENTED' | null

  ci: { pass: number; fail: number; running: number; pending: number; total: number }
  mergeable: 'CLEAN' | 'CONFLICTS' | 'UNKNOWN' | 'BLOCKED'

  additions: number; deletions: number; changedFiles: number
  opened: string         // ISO
  mergedAt?: string      // ISO
  lastActivity: string   // ISO

  reviewers: { login: string; state: 'APPROVED' | 'CHANGES_REQUESTED' | 'PENDING' | 'COMMENTED' }[]
  labels: string[]
  unread?: boolean

  // Optional preview snippets
  attentionHint?: string
  mentionHint?: string
  involvedHint?: string
}
```

Timeline events (`TIMELINE_5107`) use this shape:

```ts
type TimelineEvent =
  | { type: 'commit'; id; at; actor; title; sha; seen?; isNew? }
  | { type: 'opened'; id; at; actor; title; seen?; isNew? }
  | { type: 'comment'; id; at; actor; body; seen?; isNew? }
  | { type: 'review'; id; at; actor; state: 'APPROVED'|'CHANGES_REQUESTED'|'COMMENTED'; body; seen?; isNew? }
  | { type: 'status'; id; at; title; details?: string[]; seen?; isNew? }
```

## Tweaks (optional in production)

The Tweaks panel (bottom-right floating card in the prototype) is a designer-facing knob set. In production you may keep these as user preferences:

- **Rail palette** — Roles (default) / Saturated / Muted / Urgency.
- **Show CI gauge dots in list** — boolean, default true.
- **Show preview snippet** — boolean, default true.

If you don't expose them, hardcode the defaults above.

## Assets

No bitmap images. All icons are inline SVGs in `I` (see `ui-primitives.jsx`). Avatars are generated initials on a per-user color tint (no profile photos).

## Out of scope (intentionally not covered by these mocks)

- File-diff view, inline-comment threads on diffs
- Multi-repo aggregation UI (the repo selector dropdown is a stub)
- Notification-center / menu-bar indicator (`tweaks-menubar.jsx` is an earlier exploration, not the target)
- Auth / login flow
- Settings screen

Ask before designing these — they're deliberately not specified here.
