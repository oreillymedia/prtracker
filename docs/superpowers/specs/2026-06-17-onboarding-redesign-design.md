# Onboarding Redesign — Design

_Date: 2026-06-17 · Branch: `onboarding`_

## Context

PRTracker's first-run onboarding is a bare two-stage inline form (paste token →
type one `owner/name`). It predates multi-repo support, gives little guidance,
and doesn't feel macOS-native. We're reimagining it as a refined, guided,
stepped setup that (a) explains what's happening at each step, (b) supports
adding **multiple** repositories with validation, and (c) can be **re-run** later
from a menu command to reconfigure.

## Goals

- A polished, native, professional stepped setup with a left **step sidebar**
  (Welcome → Connect → Repositories → Notifications), matching the app's Liquid
  Glass styling.
- Guidance and context on every step (what a token is, which scope, how repos
  and notifications work).
- Multi-repo aware: add several validated repositories before finishing.
- Per-repo notification levels set during setup, with inline macOS permission.
- A menu command to re-run onboarding to reconfigure an existing install.

## Non-goals

- A repo *picker* backed by a repo-list API (we use typed `owner/name` +
  validation). 
- GitHub Enterprise / custom hosts (api.github.com only, as today).
- Changing the enable/disable concept (that stays in Settings → Repositories).

## Flow

Four steps shown in a left sidebar rail (state: done ✓ / active / upcoming;
visited steps are clickable to go back), with Back/Continue at the bottom:

1. **Welcome** — app name, one-line value prop, brief "what you'll set up", Get Started.
2. **Connect GitHub** — token field; explains the required `repo` scope; a
   "Create a token on GitHub →" button deep-linking to the PAT page with the
   scope prefilled (`https://github.com/settings/tokens/new?scopes=repo&description=PRTracker`,
   fine-grained tokens also work). **Validate** saves the token to the Keychain
   and calls `client.validate()`; on success shows the user's avatar + login (✓)
   and enables Continue; on failure shows an inline error and clears the token.
3. **Repositories** — type `owner/name`, **Add** → verify via a new
   `client.repository(_:)` call before it joins the list. Row states: checking
   (spinner) / added / "Not found or not accessible". Each added repo is listed
   with a remove (✕). Duplicate guard. Continue requires ≥1 repo.
4. **Notifications** — one row per added repo with a level picker
   (Everything / Personal / None, default **Personal**), plus an "Enable macOS
   notifications" button reflecting permission status (Not requested / Granted /
   Denied → hint to System Settings). Inline; not required to finish.

**Finish** — "Tracking N repositories" summary → `commit()` → enter the app.

## Two entry modes

`OnboardingView(mode:)` with `enum Mode { case firstRun, reconfigure }`:

- **firstRun** — shown by `RootView` in place of `MainView` when `signedIn` is
  false (as today). Starts blank. No Cancel (there's nothing to return to).
- **reconfigure** — presented as a **`.sheet`** over `MainView`, triggered by the
  menu command (below). **Pre-filled** from current state: Connect shows
  "Connected as @login" with an optional new-token field; Repositories lists the
  existing repos; Notifications shows their current levels. Has a **Cancel** that
  dismisses with no changes.

## Architecture / components

Replaces the current `OnboardingView`. New files under `Views/Onboarding/`:

- **`OnboardingModel.swift`** — `@Observable` holding all transient state: `mode`,
  `token`, validated `viewer: UserDTO?`, `pendingRepos: [PendingRepo]` (`owner`,
  `name`, `id`, `level`, and — for reconfigure — the existing
  `persistentModelID`/`isEnabled` to preserve), `notifStatus`, `currentStep`, and
  per-add validation state. Owns the step-gating logic (`canContinue(step:)`) and
  `commit(into:)`. This is the unit under test; the views stay thin.
- **`OnboardingView.swift`** — container: hosts the rail + the current step view +
  Back/Continue/(Cancel) bar; injects the model. Calls `onReady`/dismiss on finish.
- **`OnboardingStepRail.swift`** — the left step list.
- **`Steps/WelcomeStepView.swift`, `ConnectStepView.swift`,
  `RepositoriesStepView.swift`, `NotificationsStepView.swift`** — focused
  per-step content taking the model.

**Reuse:** `GitHubClient.validate()`, `NotificationAuthorization`, `AvatarView`,
design `Tokens`/Typography helpers, `.glassProminent` buttons, `Keychain`.

**New API:** `GitHubClient.repository(_ ref: RepoRef) async throws -> RepoDTO`
using the existing `Endpoints.repo(_:)`, with a minimal `RepoDTO`
(`full_name`, `private`, `default_branch`). 404/403 surface as
`repoNotFound`/`unauthorized` (already mapped in `send`).

**Extraction (small dedup, addresses a prior review finding):** add
`RepoRef.parse(_ string:) -> RepoRef?` (trim, split on `/`, require two
non-empty parts) and route the onboarding add, `SettingsView`, and
`RepositoriesSettingsView` `owner/name` parsing through it.

## Data flow & persistence

- Token → Keychain on successful Validate (required for `validate()` and
  `repository()` calls, which read the token from the Keychain).
- **firstRun commit:** insert `User` + `ViewerState(viewer:)` if absent; insert a
  `Repo(owner:name:)` per pending repo (enabled by default) with its chosen
  `notificationLevel`; save; `onReady()` (which starts the coordinator). The
  first sync baselines silently (`lastFetchedAt == nil`), so no notification flood.
- **reconfigure commit (reconcile by repo id):**
  - If the token changed and re-validated, update the Keychain and
    `ViewerState.viewer` to the new viewer.
  - For each pending repo: existing `Repo` with that id → update
    `notificationLevel`, preserve `isEnabled`; otherwise insert a new enabled
    `Repo` with the chosen level.
  - Existing `Repo`s absent from the pending list → delete (cascade removes their
    PRs).
  - Save; dismiss the sheet.

## Menu command

In `PRTrackerApp`'s `.commands`, add (near "Check for Updates…"):
`Button("Set Up PR Tracker Again…") { appState.showReconfigure = true }`.
Add `var showReconfigure = false` to `AppState` (`@Observable`). `MainView`
attaches `.sheet(isPresented: $appState.showReconfigure) { OnboardingView(mode: .reconfigure, …) }`.

## Navigation & guards

- Back available except on Welcome; Cancel only in reconfigure.
- Continue gated by `canContinue`: Connect needs a validated viewer (firstRun) or
  an already-connected/edited token (reconfigure); Repositories needs ≥1 repo.
- Sidebar: completed + active steps are clickable; upcoming steps are disabled
  until reachable.

## Error handling

- Token rejected → inline message, Keychain token cleared, stay on Connect.
- Repo add: not found / no access / network → inline per-add error, repo not added.
- Notification permission denied → inline hint pointing to System Settings; Finish
  still allowed.
- Network errors are surfaced inline with the action re-enabled for retry.

## Testing

Logic lives in `OnboardingModel`, tested against an in-memory `ModelContainer`
(via `TestContainer`) + a fake `GitHubClient`/repo-verifier:

- `RepoRef.parse` — valid, whitespace, missing slash, empty parts, extra slashes.
- `canContinue(step:)` gating for each step in both modes.
- `commit()` firstRun — inserts the expected `Repo` rows with correct levels;
  creates `ViewerState`.
- `commit()` reconfigure — kept repos retain their row/PRs with updated level,
  removed repos deleted, new repos inserted, viewer updated on token change.

## Verification

1. Build: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build`
2. Tests: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test`
3. Manual (`run` skill):
   - Fresh install (no Keychain token / no repos): full first-run flow; reject a
     bad token; add a real + a bogus repo (bogus rejected); set per-repo levels;
     grant permission; finish → lands in the app with the repos tracked, no
     notification storm.
   - Menu → "Set Up PR Tracker Again…": sheet opens pre-filled; remove a repo, add
     another, change a level, Cancel → nothing changed; reopen, make the same
     edits, Finish → reconciled (kept repo keeps its PRs, removed repo gone, new
     repo synced).
