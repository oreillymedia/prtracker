# Token Connection Overhaul — Design

_Date: 2026-09-22 · Branch: `ticket/better-api-key`_

## Context

Users get GitHub tokens wrong and the app doesn't tell them how. The app
validates **identity** (`GET /user`) and never **capability**: a token with no
scopes, no SSO authorization, no repo access, or a 30-day expiry passes the
Connect step and fails later, on a different screen, in different words.

Audit of the current state (v0.6.5):

- Four decisions left to the user with one sentence of guidance: classic vs
  fine-grained, which scopes/permissions, SSO authorization for `oreillymedia`,
  and expiration.
- Validation at four depths: onboarding Connect checks `/user` only (and
  doesn't trim input); onboarding add-repo checks `GET /repos/{o}/{r}`;
  Reconnect checks `/user` + every enabled repo; Settings → Repositories → Add
  checks nothing.
- Errors surface in six places with six vocabularies: reauth banner, sidebar
  footer (7 strings, last-repo-wins, no action), detail view (raw enum dump),
  Connect step, Reconnect sheet, repo-add flows. Per-PR failures inside the
  sync task group are swallowed entirely.
- Signals GitHub already sends are ignored: `X-OAuth-Scopes`,
  `GitHub-Authentication-Token-Expiration`, `X-GitHub-SSO` (both the 403
  `required; url=…` form and the 200 `partial-results; organizations=…` form).
- Sign out deletes the token but leaves sync running → 401 → "expired or
  revoked" banner, and the client sends unauthenticated requests meanwhile.

OAuth device flow is **off the table for business reasons**. The token stays
user-made, so the app must do the checking the user can't.

Org policy confirmed 2026-09-22: classic and fine-grained PATs both allowed,
no maximum lifetime.

## Goals

- One blessed token recipe, walked through step-by-step inside the app,
  including the SSO authorization step users currently skip.
- Every entry point (Connect, Reconnect, add-repo in onboarding and Settings)
  verifies **capability** with the same shared check.
- Every failure renders from one error vocabulary with a title, a one-line
  explanation, and where possible a button that performs the fix.
- One place (Settings → Account) shows the whole connection state and can
  re-check it on demand.

## Non-goals

- OAuth / device flow / GitHub App sign-in.
- GitHub Enterprise hosts.
- Reading the token out of the `gh` CLI (sandbox blocks its config).
- A separate fine-grained wizard. Fine-grained tokens are supported via
  detection + probes, not documented as a primary path.

## Blessed recipe (classic PAT)

Shown as a numbered checklist in both Connect and Reconnect, mirroring the
GitHub page top to bottom:

1. Click **Create a token on GitHub** (prefilled:
   `https://github.com/settings/tokens/new?scopes=repo&description=PRTracker`).
2. **Expiration:** choose *No expiration*. (Any shorter choice works; the app
   will warn a week before it lapses.)
3. Click **Generate token**, copy it, paste below.
4. On the token's row click **Configure SSO → Authorize** for `oreillymedia`.
   Without this the token signs in but can't see any org repository.

One line below the checklist: "Fine-grained tokens also work: resource owner
`oreillymedia`, the repositories you'll track, permissions **Pull requests:
Read** and **Checks: Read**."

## The shared connection check

`ConnectionCheck` (new, `GitHub/ConnectionCheck.swift`) runs against the
current keychain token and returns a list of items, each `ok / warning /
failure` with a message and optional action URL. Used by Connect, Reconnect,
and Settings → Account.

| Item | How | Failure message / action |
|---|---|---|
| Identity | `GET /user` | "GitHub rejected this token." |
| Token type | prefix `ghp_` / `github_pat_` / other | informational |
| Scope (classic only) | `X-OAuth-Scopes` contains `repo` | "Token is missing the `repo` scope. Create a new one with the link above." |
| Expiry | `GitHub-Authentication-Token-Expiration` | warning if < 30 days at Connect; stored for the sidebar warning |
| SSO (pre-repo) | `GET /user/orgs`, look for `X-GitHub-SSO: partial-results` | warning: "This token isn't authorized for one or more of your organizations. Configure SSO on the token's page." → link to tokens page |
| Per repo: reachable | `GET /repos/{o}/{r}` | 404: "Not found, or the token can't see it." 403 + `X-GitHub-SSO: required; url=` → **Authorize for {org}** button opening that URL |
| Per repo: pulls | `GET /repos/{o}/{r}/pulls?per_page=1` | "Token can't read pull requests here. Fine-grained tokens need *Pull requests: Read*." |
| Per repo: checks | `GET /repos/{o}/{r}/commits/{default_branch}/check-runs?per_page=1` | "Token can't read CI checks here. Fine-grained tokens need *Checks: Read*." |

The two per-repo probes cover every endpoint the sync uses (pulls, reviews,
review comments, timeline, check-runs). A classic `repo` token always passes
them; they exist to catch fine-grained permission gaps at add time instead of
as silently missing CI.

Pending-approval note: when a fine-grained token gets 404/403 on an org repo,
the message adds "If you just created a fine-grained token, `oreillymedia` may
still need to approve it."

## One error vocabulary

`GitHubError` gains `.ssoRequired(authorizeURL: URL)` (parsed from the 403
header before falling back to `.forbidden`). A single
`GitHubError.userFacing` (or a small `ProblemText` mapping in one file)
yields `title`, `detail`, `action: (label, URL)?`. All surfaces render from it:

- Reauth banner (401 → "GitHub sync paused · Your token expired or was revoked · Reconnect").
- Sidebar footer (shows the mapped title; click opens Settings → Account).
- Detail view (mapped title + "Retry", no more `String(describing:)`).
- Connect / Reconnect / add-repo inline errors.

Remove the unreachable `.unauthorized` branch from the sidebar mapping
(401 always routes to `needsReauth`).

## Settings → Account becomes the health page

- Signed in as (avatar, name, login) · Token type · Scopes · Expires on.
- One row per enabled repo: ✓ or ✗, reason, fix button (Authorize / open
  token page).
- **Check again** reruns `ConnectionCheck`.
- **Sign in / Reconnect** button when not signed in or `needsReauth`.
- **Sign out** stops the coordinator, deletes the token, clears the viewer,
  shows "Not signed in" (never the expired banner).

## Per-repo state

- `Repo.lastSyncErrorRaw: String?` recorded by the coordinator per repo
  (replacing last-repo-wins `lastSyncError` as the only signal). Badged in the
  repo switcher; cleared on the next successful pass.
- The per-PR task group returns the first `GitHubError` that is
  `.forbidden`/`.ssoRequired`/`.repoNotFound` instead of `false`, so a
  permission gap becomes a repo warning rather than absent CI.

## Expiry

- Store the expiration date (ViewerState) on every successful check.
- Sidebar: "Token expires in N days · Reconnect" from 7 days out.
- Connect: warning if the new token expires in < 30 days, pointing at the
  Expiration dropdown.

## Hygiene

- Trim the pasted token in Connect (Reconnect already does).
- Same prefilled create-token link in Connect and Reconnect.
- Settings → Repositories → Add runs the per-repo check before inserting
  (reuse the onboarding path).
- Connect's catch-all no longer reports a network failure as "rejected" or
  deletes the token for it.

## Phasing

1. **Vocabulary and traps** (~2 days): error mapping + `.ssoRequired` with
   button, scopes/expiry headers read at Connect, trim, Sign out fix, Settings
   add-repo verification, unified link.
2. **Shared check and checklist** (~3 days): `ConnectionCheck` used by
   Connect, Reconnect, Account; checklist copy; per-repo probes at add time.
3. **Health page and per-repo state** (~2 days): Account page rebuilt around
   check results; `Repo.lastSyncErrorRaw` + switcher badge; sidebar expiry
   warning; per-PR error bubbling.

## Verification

- Unit: `ConnectionCheck` against `StubURLProtocol` for each row of the table
  (scope header missing, SSO 403 header parsed to URL, partial-results header,
  expiry header parsed, pulls/checks probe 403).
- Unit: `GitHubError` → user-facing mapping covers every case.
- Manual: paste a scopeless classic token → fails at Connect with the scope
  message. Paste an un-SSO'd `repo` token → Connect warns; adding an
  `oreillymedia/*` repo shows the Authorize button; after authorizing, Check
  again turns the row green. Paste a fine-grained token with only Pull
  requests: Read → add-repo fails naming *Checks: Read*. Sign out → "Not
  signed in", no banner, no network calls.
