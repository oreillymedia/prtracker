# PRTracker v0.6.0

## What's new

- **Times that stay honest.** "Last activity" now reflects the *real* latest activity on a pull request — a new comment or review updates it immediately, even when GitHub itself doesn't move the PR's timestamp. The pull-request list reorders by true activity, so the thing that just changed rises to the top.
- **Relative times tick on their own.** "2m ago" now advances by itself instead of sitting frozen until the next sync, so what you see always matches the clock.
- **A dedicated fast lane for the PR you're reading.** The open pull request refreshes on its own tighter schedule and shares the same data path as the background sync, so its conversation, reviews, and timestamps never lag behind — or disagree with — the list.

## Fixes

- **"Last activity" no longer freezes or reads out of order.** Previously, while you were looking at a PR, new comments would appear in the thread but the activity time (and the PR's place in the list) wouldn't move until the next full background sync — and could even show older than "Last checked." Both now update the moment new activity arrives.
- **The sidebar's "Updated" time is now trustworthy.** It advances only when *every* repository synced successfully, so one healthy repo can no longer mask another that's failing or stalled.
- **No more phantom "just now" events.** Timeline entries that arrived without a date used to display as if they'd just happened; they now fall back to the PR's open time.

## Notes

- Under the hood this is a consolidation: a single sync scheduler (replacing two loops that could drift apart), a locally-derived activity time, and conditional requests (ETags) now applied to the PR-list fetches too — so despite the tighter refreshing, GitHub API and rate-limit usage go *down*.
- On first launch after updating, PRTracker briefly backfills activity times for your existing pull requests so the list sorts correctly right away.
- The menu-bar item remains disabled in this build — PRTracker runs as a regular window for now.
