# Liquid Glass Migration — Design

**Date:** 2026-06-04
**Status:** Approved (design); pending implementation plan
**Branch:** `liquid-glass`
**Target:** macOS 26.4 (Tahoe), Xcode 26 SDK

## Goal

Convert PRTracker's UI to Apple's Liquid Glass design language, the right way:
move the app onto the standard SwiftUI navigation chrome that adopts glass
natively, and retire the hand-rolled translucency that approximated depth before
the system could provide it. Glass is applied **only** to the navigation/control
layer; content surfaces stay opaque.

## Background — why a structural migration

PRTracker today is a custom three-pane layout: `MainView` lays out a manual
`HStack` of `MailSourceColumn` (a fixed 380pt sidebar) and either `PRDetailView`
or `MailEmptyDetailView`. There is no `NavigationSplitView`, no `.toolbar`, and
no `.inspector()`. Depth is faked by a `Tokens` enum full of semi-transparent
`NSColor` fills (`panelBg`, `sidebarBg`, `cardBg`, `border`, `hairline`).

Liquid Glass auto-adopts on **standard** navigation components. Because almost
nothing here is standard, a compile-only pass would change almost nothing.
Adopting glass correctly — and getting Reduce Transparency / Increase Contrast
behavior for free — requires moving onto the standard components. We chose the
**full architectural migration** over targeted glass or compile-only.

## Core principle

> Glass is for the navigation/control layer (sidebars, toolbars, inspectors,
> floating buttons) that floats above content. Never apply glass to content
> (lists, cards, timeline rows, text, media).

Two consequences enforced throughout:
- Content surfaces (thread cards, timeline rows, review-comment cards, empty
  state) become **solid** surfaces, never `.glassEffect()`.
- Glass can't sample glass: glass controls never float directly on the glass
  sidebar; grouped glass controls share a `GlassEffectContainer`.

## Architecture — main window

Replace `MainView`'s `HStack` with a `NavigationSplitView`:

- **Sidebar** (system glass, neutral — the existing blue tint is dropped):
  repo selector + filter control + grouped PR list + account footer.
  - The filter (currently `FilterPillBar`, custom capsule pills) moves into the
    **sidebar toolbar as a segmented control** (`Picker`/segmented), which
    adopts glass correctly and avoids glass-on-glass artifacts.
  - PR list keeps its lane-grouped rows, lane stripes, selection highlight.
- **Detail** (`PRDetailView`): thread/timeline as solid content with:
  - A glass `.toolbar`: refresh, Open on GitHub (`Link`), inspector toggle.
    Toolbar items adopt glass automatically; cluster shares a
    `GlassEffectContainer`.
  - PR title via `.navigationTitle`; the author/branch metadata + `TodoSummaryBar`
    remain as an inline content subheader below the toolbar.
- **Inspector** (`.inspector()`, toggleable): the current `DetailRightRail`
  (Status / CI / Reviewers / Labels / Changes / Opened / Updated). Gets native
  glass + trailing-edge slide; toggled from the toolbar.

## `Tokens` refactor

Split the `Tokens` enum:

- **Keep (semantic content colors):** `accent`, `accentText`, `accentBg`,
  `approved`/`changes`/`pending`/`commented` and their `*Bg` tints, `text`,
  `textMuted`, `textFaint`, `unreadDot`, `newHighlight`, `rowSelect`, `rowHover`.
  Lane colors (`LaneColors`) unchanged. These are identity and live on content.
- **Retire (simulated materials):** `windowBg`, `panelBg`, `sidebarBg`,
  `contentBg`, `cardBg`, `border`, `borderStrong`, `hairline`. Replaced by:
  - Navigation chrome: no explicit background — system glass via
    `NavigationSplitView` / `.inspector()` / `.toolbar`.
  - Content surfaces: solid `.background(.background)` /
    `WindowBackgroundShapeStyle.windowBackground`; real `Divider()` instead of
    hairline rectangles.

The deletion is compile-error-driven: removing the constants surfaces every call
site for deliberate replacement.

## Controls

- Glass: detail toolbar buttons (automatic), `QuickReply` send
  (`.glassProminent`), Onboarding primary (`.glassProminent`) / secondary
  (`.glass`). Apply `.tint(.clear)` on macOS glass buttons where needed for
  correct rendering.
- Content (no glass): filter segmented control (toolbar, system-styled), status/
  CI/label chips, lane stripes, todo rings, avatars, markdown.
- Grouping: adjacent glass controls share a `GlassEffectContainer` (toolbar
  cluster, menu-bar action row).

## Other surfaces

- **Menu-bar popover** (`MenuBarContentView`): list stays content; bottom action
  rows (Open / Refresh / Preferences / Quit) become glass buttons in a
  `GlassEffectContainer`; `Tokens` hairlines → system `Divider()`. Popover chrome
  is system-provided.
- **Onboarding** (`OnboardingView`): glass primary/secondary buttons; retire
  `cardBg`/`contentBg` fills, glass on the action layer only.
- **Settings** (`SettingsView`): lightest touch — standard controls restyle under
  the SDK; remove any custom `Tokens` backgrounds and let it be.

## Accessibility

- System glass/materials respond to **Reduce Transparency** and **Increase
  Contrast** automatically (the payoff vs. hand-rolled translucency).
- `.glassEffect()` on custom views honors `.identity` under Reduce Transparency
  to degrade cleanly to opaque.
- **Reduce Motion** tames specular/morph animation.
- Verify all four toggles in light + dark.

## Sequencing

Incremental on the `liquid-glass` branch; each step compiles and keeps tests
green:

1. Split `Tokens` (delete material constants, keep semantic colors).
2. Main window → `NavigationSplitView` (sidebar + detail), `.navigationTitle`.
3. Detail chrome → `.toolbar` + inline subheader.
4. Right rail → `.inspector()`.
5. Filter pills → sidebar-toolbar segmented control.
6. Glass on controls + `GlassEffectContainer` grouping.
7. Menu-bar popover, Onboarding, Settings touch-ups.

## Testing & verification

- Existing test suite (model / sync / notification / classifier logic; no view
  snapshots) must stay green — acts as a behavioral safety net through the UI
  refactor.
- `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`.
- Manual verification at the end: build, run, visually confirm each surface in
  light/dark + Reduce Transparency / Increase Contrast / Reduce Motion.

## Out of scope (YAGNI)

- No new features.
- No menu-bar icon redesign.
- No `.backgroundExtensionEffect` (no hero imagery in this app).
- No data-model or sync changes.
