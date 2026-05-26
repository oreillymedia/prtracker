# Handoff: PR Tracker — Todo-first Mail layout

## Overview

A macOS desktop app for tracking GitHub Pull Requests. The defining pattern is **every PR is a todo list**: each comment from a reviewer is a checkable todo, replies in the same thread are sub-todos, and a thread is only "resolved" once every non-mine message in it is checked. New replies arriving in a resolved thread flip it back to open.

The app uses a **two-pane mail-style layout** (no drilling): a filterable source list on the left, a permanent detail view on the right. Selecting a row in the list swaps what's shown on the right — exactly like Mail.app, Things, or Linear's triage view.

The product audience is engineers (the persona "Alex Chen") who lose track of what they still owe across many open PRs. The app's job is to make "what needs me right now" inescapable, and "what's resolved" disappear.

**Read/unread is not part of this product.** It was deliberately removed in favor of done/not-done as the only state that matters.

## About the design files

The files in this bundle are **design references created in HTML** — interactive prototypes that show the intended look, layout, and behavior. They are NOT production code to copy directly.

The HTML uses inline React + Babel for prototyping speed. In a real codebase you should **recreate the design in the target app's environment** (SwiftUI for a real Mac app, Electron + React, native AppKit, etc.) using its established patterns. If no environment exists, SwiftUI is the natural choice for a Mac-only app; Electron + React is appropriate if cross-platform is required.

## Fidelity

**High-fidelity.** Spacing, type, color, and component states are intentional and should be matched closely. Where the spec gives a pixel value, treat it as the target; where it describes a behavior, match the visual effect.

## Files in this bundle

| File | Role |
|---|---|
| `PR Tracker.html` | Entry HTML. Loads scripts and renders a design-canvas of four artboards demonstrating different states. |
| **`pr-mail.jsx`** | **The main deliverable.** Source list, filter pills, thread cards with checkboxes, todo summary bar, all the todo plumbing. |
| `pr-detail.jsx` | Re-used helpers from the previous variant — `CIBreakdown`, `RailSection`, `RailRow`, `btnPrimaryStyle`, `btnSecondaryStyle`. Only those helpers are still in use. |
| `feed-lanes.jsx` | `LANE_COLORS` palette tokens and `priorityFor` helper (used by `bucketFor` in `pr-mail.jsx` to choose the source-list rail color). The other exports here are unused. |
| `ui-primitives.jsx` | Theme tokens (`THEMES.light`, `THEMES.dark`), `Avatar`, icons (`I`), `ReviewPill`, `CIPill`, `MergeablePill`. Source of truth for color and iconography. |
| `mac-shell.jsx` | `MacShell` window chrome (traffic lights, drop shadow). |
| `data.jsx` | Mock data: `PULL_REQUESTS`, `USERS`, `ME`, `REPOS`, the `threads` arrays on each PR, plus the todo helpers `threadIsResolved`, `threadHasNew`, `threadOpenCount`, `prTodoCounts`, and `relTime`. |
| `design-canvas.jsx` | Prototype-only artboard host. Not part of the product. |
| `pr-mail-v1.jsx` | **Predecessor for reference only.** The non-todo version of the mail layout that this design replaced. Useful for diffing if you want to see what changed. Don't ship it. |

## The core idea: todos derived from threads

A PR has a list of **threads**. A thread starts with a comment from a reviewer (a general PR comment, or a review-comment attached to a code location) and accumulates replies.

```ts
type Thread = {
  id: string
  kind: 'review-comment' | 'pr-comment'
  where: string              // 'general' or 'BadgeFetcher.swift L142'
  kindLabel?: string         // e.g. 'Changes requested' for emphasized threads
  messages: Message[]
}

type Message = {
  id: string
  actor: string              // login key into USERS
  at: string                 // ISO timestamp
  body: string
  isMine?: boolean           // true when authored by the current user
  done?: boolean             // user has marked this addressed
  isNew?: boolean            // arrived since user last engaged
}
```

### Rules (these drive the entire UI)

1. **A message is a todo iff it is not mine** (`!isMine`). My own replies show with a "You" tag and have no checkbox — they're contributions, not todos.
2. **A thread is resolved iff every non-mine message in it has `done === true`.** My own messages don't affect resolution either way.
3. **A new reply from someone else** in an otherwise-resolved thread makes it un-resolved again (because the new message has `done: false`).
4. **"Resolve all"** on a thread sets every non-mine message's `done` to true.
5. **"Reply" inside a thread**, in the prototype, also resolves the thread (replying is taken to mean "I've addressed it"). In production, treat this as a default — let users opt out, e.g. with a "Reply without resolving" affordance, but the default action of the green button should resolve.

### Helpers

```js
threadIsResolved(thread) // bool: all non-mine messages have done=true
threadHasNew(thread)     // bool: any non-mine, !done, isNew message
threadOpenCount(thread)  // number: count of non-mine, !done messages
prTodoCounts(pr)         // { total, done, open, openMessages }
                         //   total/done/open are thread counts
                         //   openMessages is the sum of open non-mine messages across all open threads
```

`prTodoCounts` is what drives the source-list ring and the detail-pane summary bar.

## Layout

Window is **1280 × 820** in the prototype, but the app should be **resizable**. Two columns, no top toolbar:

```
┌──────────────────────────┬──────────────────────────────────────────┐
│  Source list (380px)     │  Detail pane (flex)                      │
│  ────────────────────    │  ──────────────                          │
│  • Traffic lights        │  • Detail header                         │
│  • Repo selector         │    – breadcrumb / status / refresh       │
│  • Filter pills strip    │    – title (17px bold)                   │
│  • List of PRs (scroll)  │    – author/branch metadata              │
│  • Account footer        │    – Todo summary bar                    │
│                          │  • Body: threads | meta rail (232px)     │
│                          │    – Open section + thread cards         │
│                          │    – Resolved section + thread cards     │
│                          │    – meta rail: Status / CI / Reviewers  │
│                          │      / Labels / Changes                  │
└──────────────────────────┴──────────────────────────────────────────┘
```

---

## Left pane — Source list (width: 380, fixed)

Glassy background (`rgba(210,225,245,0.45)` light, `rgba(44,44,46,0.55)` dark) with `backdrop-filter: blur(40px) saturate(180%)`. `border-right: 0.5px solid` theme border.

### Top stack (above the list)

1. **Traffic-lights row** — 38px tall, 12px gutter. Red `#ff5f57`, yellow `#febc2e`, green `#28c840`; 12×12 circles with 0.5px black-15% stroke.

2. **Repo selector** — 8px gap below traffic lights, 12px horizontal padding. Card with `cardBg`, `0.5px solid border`, `border-radius: 7`, `padding: 6px 10px`. Left: 22×22 rounded-5 gradient tile (`linear-gradient(135deg, #c96442, #7b2d1a)`) with white "SP" 10px 700. Middle: org (11px muted) / repo name (13px 600). Right: chevron-down 10px faint.

3. **Filter pills strip** — 8px top / 10px bottom padding, 12px horizontal, 6px gap. `border-bottom: 0.5px solid hairline`. Horizontal scroll (no scrollbar).

   Pills in order: **All · Awaiting me · Open · Mentions · Mine · Done · Merged**

   - Default pill: `border-radius: 999`, `padding: 4px 9px 4px 10px`, `font: 11.5px 600`, `0.5px solid border`, `background: cardBg`, `color: text`.
   - Active (any filter): `background: text`, `color: #fff`, transparent border (looks like a dark inverted pill in light mode).
   - **"Awaiting me" is special**: when its count > 0, the inactive pill uses `background: accentBg`, `color: accent`, `weight: 700`. When active, `background: accent`, `color: #fff`. This is the only pill that visually shouts.
   - Count badge inside each pill: 10px 700, tabular-nums, right of the label. `color: textMuted` (or `accent` when awaiting-me) / `#fff` at 85% when the pill is active. Hidden when 0.

### Source-list rows

`padding: 10px 12px 11px 14px`, `border-bottom: 0.5px solid hairline`, `cursor: pointer`. Selected = `background: rowSelect`; hovered = `background: rowHover`; otherwise transparent.

**Priority rail** — absolutely positioned, `left: 0`, `top: 6, bottom: 6`, `width: 3`, `border-radius: 2`. Color from the lane palette for the row's bucket:

```
bucket (priority order)            color (Roles palette)
────────────────────────────       ─────────────────────
pr.state === 'MERGED'              recent     #8250df
ballInMyCourt(pr)                  attention  #ff9500
pr.needsMyReview                   review     #0a84ff
pr.mention                         mentions   #bf5af2
pr.mine && state === 'OPEN'        mine       #30b94d
otherwise                          involved   #8e8e93
```

When the row is dim (merged or fully resolved & not selected), the whole row drops to `opacity: 0.55` and the rail to `opacity: 0.5`.

**Row layout** — 10px gap, items aligned to flex-start:

#### TodoRing (left)

24×24 SVG circular progress.

- **Track**: `hairline` color stroke, `stroke-width: 2.5`.
- **Fill arc**: rotated −90deg so it starts at 12 o'clock. `stroke-width: 2.5`, `stroke-linecap: round`, `stroke-dashoffset` animates over 0.35s ease.
- **Fill color**:
  - All resolved (`done === total` and `total > 0`): `approved` green
  - Awaiting me: `accent` blue
  - Open but waiting on others: `textFaint`
- **Center label**: tabular-nums `done/total`, 10px 700. When all resolved, swap to a unicode "✓" sized at `size × 0.55`. When `total === 0`, render a faint mid-dot.
- Text color matches the arc color (green/blue/muted).

The ring updates with a smooth transition whenever the count changes (e.g. you check a box in the detail view).

#### Right side of the row (flex: 1)

**Top line** — flex, baseline, gap 6:
- Title: 13px, weight 700 if awaiting-me, 500 if resolved/merged, else 600. Color = `accentText` when selected, else `text`. Single line ellipsis. `letter-spacing: -0.05`.
- Time: 10.5px tabular-nums `textFaint`.

**Second line** — 4px above first, gap 6, center-aligned:
- 15px avatar.
- Author name: 11.5px 500 `textMuted`.
- Middle dot · #num (11px tabular `textFaint`).
- Spacer (flex: 1).
- **Right-side status chip** — one of:
  - Merged: `#8250df` 10.5px 600 + merge-glyph 11px. No background.
  - Resolved (open PR, total > 0): `approved` green 10.5px 600 + check-glyph 11px, text "Caught up". No background.
  - **Awaiting me**: `accent` 10.5px 700, padding 1px 7px, radius 999, `accentBg` background. Small 5×5 pulsing dot + "N for me" (uses `openMessages`, not thread count — singularized to "1 for me" when 1).
  - Open but waiting on others: 10.5px 500 `textMuted`, text "waiting on others". No background.

**Preview line** (when present, hidden for resolved + merged):
- 5px below second line, 11.5px `textMuted`, line-height 1.4, clamped 2 lines (`-webkit-line-clamp: 2`).
- Built from the most recent open non-mine message: `"<FirstName>: <body>"` (first name in `text` 500, body in `textMuted`). Falls back to `pr.attentionHint` when no thread preview is available.

**Sort order** — awaiting-me PRs first (stable), then by `lastActivity` desc. Filter pills don't change this order, only the set.

**Empty state** — "Nothing in this filter." 12.5px italic `textFaint`, centered, padding 40.

### Account footer

`border-top: 0.5px solid border`, `padding: 10px 14px`, 8px gap. 22px avatar + name (12px 600) over @login (10.5px muted) + settings icon.

---

## Right pane — Detail (flex: 1)

Background `contentBg`.

### Detail header (10px top / 18px horizontal / 12px bottom, `border-bottom: 0.5px solid border`, `background: panelBg` with same backdrop blur)

**Toolbar row** (gap 8, 10px below: title):
- Breadcrumb: "spark-ios" (11.5px faint) · "/" · "#5107" (11.5px muted tabular)
- Middle dot · status pill (Open green / Merged purple) — 10.5px 600, padding 1px 7px, radius 999, tinted background.
- Spacer.
- "Updated Xm ago" 11px muted (clock icon 11px faint) — swaps to "Refreshing…" with a spinner while `isRefreshing`.
- 24×24 refresh button (`cardBg`, 0.5px border, radius 5). Icon spins during refresh.
- 24×24 theme toggle (sun/moon).

**Title** — 17px 700 `text`, `letter-spacing: -0.2`, `text-wrap: pretty`, line-height 1.25, margin 0.

**Metadata row** (8px below title, gap 8, flex-wrap):
- 18px avatar + author name (11.5px 500 `text`).
- "wants to merge into" (11.5px muted).
- Base branch in a hairline-background pill: monospace 10.5px, padding 1px 5px, radius 4.
- "from"
- Head branch in the same pill style.
- Middle dot · "opened Xd ago".

#### Todo summary bar (12px below metadata, hidden when PR has no threads)

```
┌──────────────────────────────────────────────────────────────┐
│ ⊙  3 of 5 threads resolved                                   │
│    2 open messages to address                                │
└──────────────────────────────────────────────────────────────┘
```

- Padding 8px 10px, border-radius 8, gap 10, align-items center.
- When **resolved**: `background: approvedBg`, `border: 0.5px solid approved44`.
- When **awaiting (open > 0)**: `background: accentBg`, `border: 0.5px solid accent33`.
- Left: 32px `TodoRing` (same component as the source list, larger).
- Body:
  - Line 1: 13px 700. "All caught up" when resolved (`approved` color), else "`{done}` of `{total}` threads resolved" (`accentText` color).
  - Line 2: 11.5px `textMuted`. "No outstanding feedback. Ready when CI is." when resolved, else "`{openMessages}` open message(s) to address".

### Detail body (flex: 1, display: flex, overflow: hidden)

Two columns.

**Left: thread list** (flex: 1, padding 14px 20px 22px, overflow auto)

Two sections, each preceded by a **SectionHeading**:

```
●  OPEN          (3)
●  RESOLVED      (2)
```

SectionHeading is: padding 8px 2px 10px, gap 8, baseline. A 6×6 dot in section color (Open = `accent`, Resolved = `approved`), the label in 11px 700 `text` UPPERCASE letter-spacing 0.6, then a count pill (11px 600 `textMuted` on `hairline` background, padding 1px 6px, radius 10).

Thread cards inside each section are stacked with `gap: 10` (Open) / `gap: 8` (Resolved). 18px margin-bottom after the Open block.

#### Thread card

```
┌───────────────────────────────────────────────────────────┐
│ [✓] BadgeFetcher.swift L218  • Resolved             ⌄    │  ← header (clickable to collapse)
├───────────────────────────────────────────────────────────┤
│ [○] 🟠 Daniel Draper                          2d ago     │  ← message 1 (open)
│        Could we extract the fallback fetch into          │
│        its own helper so the test reads cleaner?         │
│                                                           │
│ ↳   🔵 Alex Chen [YOU]                       1d ago     │  ← my reply (no checkbox)
│        Extracted resolveByName(_:issuer:) — see c88a013. │
│                                                           │
│ [✓] 🟠 Daniel Draper                         1d ago     │  ← message 2 (checked)
│        Perfect.                                          │
├───────────────────────────────────────────────────────────┤
│  [+ Reply]                                                │
└───────────────────────────────────────────────────────────┘
```

**Card chrome**:
- `border-radius: 10`, `0.5px solid border` (border color uses `accent + '66'` when the thread has new messages), `background: cardBg`.
- `box-shadow: cardShadow` when open; none when resolved.
- `opacity: 0.78` when resolved (so the Resolved section visibly recedes).
- Collapsed by default when resolved; expanded by default when open. Re-collapses if the user resolves it.

**Card header** (padding 10px 12px, gap 10, align center, cursor pointer):
- Status tile: 22×22, border-radius 6, `flex-shrink: 0`.
  - Resolved → `approved` background + white 13px check glyph.
  - Has new → `accent` background + white `{done}/{totalNonMine}` 10px 700 tabular text.
  - Otherwise → `hairline` background + `textMuted` `{done}/{totalNonMine}` text.
- Middle text:
  - Top line (baseline gap 6):
    - Optional kind label (e.g. "CHANGES REQUESTED"): 10px 700 UPPERCASE letter-spacing 0.5; color `changes` for "Changes requested", else `textMuted`.
    - Middle dot when kind label present.
    - Location: 12.5px 600 `text`. Monospace font (`ui-monospace, SFMono-Regular, Menlo`) when location is a file/line; sans for "Discussion" (the label rendered when `where === 'general'`).
  - Sub-line (margin-top 2): 11px `textMuted`. "Resolved" when resolved, else "`{openCount}` open · `{n}` message(s)".
- "Resolve all" button (only when not resolved and `totalNonMine > 1`): 11px 600 `textMuted`, padding 3px 8px, border-radius 5, `0.5px solid border`, `background: contentBg`. Stops propagation on click.
- Chevron 11px faint at right, rotated -90deg when collapsed (rotates 0deg when open) with 0.15s transition.

**Message rows** (inside the card body, padding 10px 12px, gap 10):
- `background`: `newHighlight` when the message is new and not done, transparent otherwise.
- `border-left: 3px solid transparent` normally, `3px solid accent` when new and not done.
- `opacity: 0.5` when done and not mine (gives the strikethrough faded look). Mine messages always render full opacity.
- Left rail (18px wide):
  - Non-mine message → `TodoCheckbox` (18×18, border-radius 5.04, 1.5px solid `borderStrong` when unchecked, solid `approved` background + white 12px check when checked). Hover state can deepen the border; click toggles `done` for that message and stops propagation.
  - Mine message → a faint "↳" glyph (9px 700 `textFaint` UPPERCASE letter-spacing 0.4) in place of the checkbox. No interaction.
- 22px avatar.
- Body (flex 1):
  - Header line (baseline, gap 6, margin-bottom 3):
    - Author name 12px 600 `text`. Strikethrough (`text-decoration: line-through` with `text-decoration-color: textFaint`) when message is done and not mine.
    - "YOU" tag (when mine): 9.5px 700 `textMuted`, padding 1px 5px, border-radius 3, `hairline` background, UPPERCASE letter-spacing 0.3.
    - "NEW" tag (when new and not done): 9.5px 700 `accent`, padding 1px 6px, border-radius 3, `accentBg` background, UPPERCASE letter-spacing 0.4.
    - Spacer.
    - Time: 10.5px `textFaint`.
  - Body text: 13px 1.5 line-height `text`, `text-wrap: pretty`. Strikethrough (decoration color `textFaint99`) when done and not mine.

**Inline reply** (footer of the card body, padding 8px 12px 10px, `border-top: 0.5px solid hairline`, `background: panelBg`):
- Default state: a dashed-border button (`0.5px dashed border`, transparent background, 11.5px 500 `textMuted`, padding 4px 8px, border-radius 5) showing a comment icon + "Reply".
- Active state: a textarea (min-height 54, padding 8, border-radius 6, 0.5px border, `contentBg`, 12.5px) with auto-focus; below it, "Cancel" (secondary button) and "Reply & resolve" (primary, disabled until non-empty). The primary action sends the reply AND resolves the thread.

**Empty state** — When the PR has no threads at all: a single card with `padding: 24`, `border-radius: 10`, `cardBg`, `0.5px border`, 13px `textMuted` centered: "No threads on this PR yet."

**Right: meta rail** (width 232, `border-left: 0.5px solid border`, padding 16, overflow auto, `background: panelBg`)

RailSections in order, same as the predecessor design:
1. **Status** — Review pill / CI pill / Mergeable pill.
2. **CI checks** — list of `{label, state, time}` rows.
3. **Reviewers** — avatar + name + review pill per reviewer.
4. **Labels** — flex-wrap pills.
5. **Changes** — "+N −N · M files".

Section label = 10.5px 700 UPPERCASE `textFaint` letter-spacing 0.6, 8px below the content.

The previous "Mark all as unread" button is **removed**. There is no read state anymore.

### Empty detail state

When no PR is selected (only possible if the filter is empty): centered 28px PR-icon at `textFaint` 0.5 opacity, "No pull request selected." 13px `textFaint`, 8px gap column.

---

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
accent       #007aff      accentBg rgba(0,122,255,0.10)    accentText #0062cc
approved     #1a7f37      approvedBg rgba(26,127,55,0.10)
changes      #cf222e      changesBg  rgba(207,34,46,0.10)
pending      #9a6700      pendingBg  rgba(154,103,0,0.10)
commented    #6e7781      commentedBg rgba(110,119,129,0.10)
cardBg       #ffffff      cardShadow 0 1px 2px rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.05)
rowHover     rgba(0,0,0,0.03)
rowSelect    rgba(0,122,255,0.10)
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
accent       #0a84ff      accentBg rgba(10,132,255,0.18)   accentText #64a9ff
approved     #3fb950      approvedBg rgba(63,185,80,0.15)
changes      #f85149      changesBg  rgba(248,81,73,0.15)
pending      #d29922      pendingBg  rgba(210,153,34,0.15)
commented    #8b949e      commentedBg rgba(139,148,158,0.15)
cardBg       #2c2c2e
rowHover     rgba(255,255,255,0.04)
rowSelect    rgba(10,132,255,0.20)
newHighlight rgba(10,132,255,0.08)
```

## Typography

System font stack: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro", "Helvetica Neue", sans-serif` with antialiased smoothing. **Do not introduce a custom typeface.**

| Use | Size | Weight | Letter-spacing | Notes |
|---|---|---|---|---|
| Detail title | 17 | 700 | −0.2 | text-wrap: pretty, line-height 1.25 |
| Source-list title (awaiting) | 13 | 700 | −0.05 | single line, ellipsis |
| Source-list title (default open) | 13 | 600 | −0.05 | |
| Source-list title (resolved/merged) | 13 | 500 | −0.05 | |
| Author name | 11.5 | 500 | 0 | |
| #PR-number | 11 | 400 | 0 | tabular-nums |
| Time | 10.5 | 400 | 0 | tabular-nums, faint |
| Repo name | 13 | 600 | 0 | |
| Repo org | 11 | 400 | 0 | muted |
| Section label (rail / detail body) | 10.5 / 11 | 700 | 0.6 | UPPERCASE |
| Filter pill label | 11.5 | 600 (700 awaiting) | 0 | |
| Thread card location | 12.5 | 600 | 0 | monospace when file-anchored |
| Thread card sub-line | 11 | 400 | 0 | muted |
| Thread card kind label | 10 | 700 | 0.5 | UPPERCASE |
| Message author | 12 | 600 | 0 | strike-through when done & not mine |
| Message body | 13 | 400 | 0 | line-height 1.5, text-wrap pretty |
| Tag chip (YOU, NEW) | 9.5 | 700 | 0.3–0.4 | UPPERCASE |
| Branch / sha pill | 10.5 | 400 | 0 | ui-monospace, SFMono-Regular, Menlo |

## Spacing & radii

- Window: `border-radius: 12`.
- Source list width: **380** (fixed).
- Meta rail width: **232** (fixed).
- Source-list row padding: **10 / 12 / 11 / 14** (T/R/B/L).
- Thread card: `border-radius: 10`, `0.5px solid border` (or accent-tinted when new).
- Message row padding: **10 / 12**, gap 10.
- Pill radius: 999.
- Button radius: 5–6.
- Hairline: `0.5px solid border` (or `hairline` token for the lightest dividers).

## Avatars

Initials (first two name parts) on a saturated per-user color fill (see `USERS`). Letter color white. Font size ≈ `size × 0.42`, weight 600, letter-spacing 0.2. Border-radius 50%. Used at sizes 15 / 18 / 20 / 22.

## Pills (review / CI / merge)

All compact pills: `padding: 1px 6px 1px 5px`, `border-radius: 999`, `font: 10.5px 600`, icon 10–11px, 4px gap.

- **ReviewPill** — solid tinted background. APPROVED / CHANGES_REQUESTED / PENDING / COMMENTED map to the four theme color pairs.
- **CIPill** — outlined (`background: transparent`, `border: 1px solid color33`). Picks dominant state: fail > running > pass.
- **MergeablePill** — text only, no background. Tiny 7px dot prefix.

---

## State

```ts
type AppState = {
  theme: 'light' | 'dark'
  activeFilter: FilterId
  selectedId: number | null

  // Per-message done-state overrides. Only stores user changes;
  // an absent entry means "use the message's intrinsic done flag".
  // Server should persist this.
  threadOverrides: Record<ThreadId, Record<MessageId, boolean>>

  isRefreshing: boolean
  lastUpdated: string
  opts: {
    palette: 'current' | 'saturated' | 'muted' | 'semantic'
    groupResolved: boolean   // split Open / Resolved sections vs. flat
    showWhere: boolean       // show file/line on thread headers
  }
}
```

**Selection auto-reconciles** when `activeFilter` changes: if the previously selected PR is still in the filter keep it, otherwise pick the first PR in the new (sorted) list, otherwise null.

**Sort order**: ball-in-my-court first (stable), then `lastActivity` desc. Applies inside every filter view.

## Interactions

- **Row click** → select PR. No animation beyond row background highlight.
- **Filter pill click** → swap `activeFilter`; list re-filters + re-sorts instantly; selection reconciles per above.
- **Refresh button** → spin icon for ~900ms, update "Updated" timestamp.
- **Theme toggle** → swap `THEMES.light` ↔ `THEMES.dark`. Instant, no transition.
- **Thread header click** → toggle collapse for that thread. Resolved threads start collapsed.
- **Checkbox click on a message** → toggle `done` for that message. The ring + summary bar update with a 0.35s ease transition; if the toggle resolves the whole thread, the thread collapses and migrates from Open to Resolved on next render.
- **Resolve all (thread header)** → set `done = true` for every non-mine message in the thread.
- **Reply button (thread footer)** → reveal the inline composer. "Reply & resolve" (primary, accent) sends the reply *and* sets `done = true` for every non-mine message in the thread. "Cancel" (secondary) collapses the composer.

## Server contract

The thread/message shape (see Helpers above) must be served by the GitHub adapter. Map GitHub review-comments and PR-comments to threads:

- A **PR review-comment thread** (review comments attached to a code location) becomes a thread with `kind: 'review-comment'` and `where: '${path} L${line}'`. Use `kindLabel: 'Changes requested'` if the review the thread originated from has state `CHANGES_REQUESTED`.
- A **PR conversation comment** (issue-style comment on the PR itself) becomes a thread with `kind: 'pr-comment'` and `where: 'general'`.
- **Reactions**, suggested-change accepts, etc. are out of scope for v1 — fold them into the messages as plain bodies or skip them.

The `done` flag is **per-user, persisted server-side**. Two users looking at the same PR will see independent done-states. Keep it in your app's own table keyed by (user, message_id).

`isNew` is true if the message has `done === false` AND was created after the user's last interaction with this PR. Heuristic: store a `last_seen_at` per (user, pr_id); compute `isNew = !done && created_at > last_seen_at`. Update `last_seen_at` on row selection.

## PR-level data shape

(unchanged from the previous handoff)

```ts
type PR = {
  id: number
  number: number
  title: string
  author: string          // login key into USERS
  repo: string
  branch: string          // head
  base: string
  state: 'OPEN' | 'MERGED' | 'CLOSED'
  isDraft: boolean

  mine: boolean
  needsMyReview?: boolean
  mention?: boolean

  review: 'APPROVED' | 'CHANGES_REQUESTED' | 'PENDING' | 'COMMENTED' | null
  ci: { pass: number; fail: number; running: number; pending: number; total: number }
  mergeable: 'CLEAN' | 'CONFLICTS' | 'UNKNOWN' | 'BLOCKED'

  additions: number; deletions: number; changedFiles: number
  opened: string         // ISO
  mergedAt?: string      // ISO
  lastActivity: string   // ISO

  reviewers: { login: string; state: 'APPROVED' | 'CHANGES_REQUESTED' | 'PENDING' | 'COMMENTED' }[]
  labels: string[]

  threads: Thread[]      // the todo list
}
```

The legacy `unread`, `needsMyAttention`, `attentionHint`, `mentionHint`, `involvedHint` fields are no longer used by the UI. They can be removed from the API once the legacy detail view is gone.

## Tweaks (optional in production)

The prototype's Tweaks panel exposes these knobs. In production you may keep them as user preferences or hardcode the defaults:

- **Rail palette** — Roles (default) / Saturated / Muted / Urgency.
- **Group resolved threads** — when true (default), split into Open + Resolved sections; when false, interleave them (still sorted with open first).
- **Show file/line on threads** — default true. When false, hide the location text in thread headers.

## Out of scope

- File-diff view, inline code blocks under thread messages.
- Multi-repo aggregation (the repo selector dropdown is a stub).
- Settings / preferences screen.
- Notification-center / menu-bar indicator.
- Auth / login flow.

Ask before designing these.
