# PRTracker v0.5.2

## What's new

- **Live conversation updates.** An open pull request now refreshes on its own about once a minute, so new comments and reviews show up without clicking refresh.
- **Sync status in the sidebar.** The source-list footer now shows when PRTracker last synced, a spinner while it's working, and a clear message if a sync fails (expired token, rate limit, or network).

## Fixes

- **Comment & review notifications now actually arrive.** Background syncing never used to fetch PR conversations, so "someone commented" and "someone reviewed" notifications effectively never fired unless you opened the PR yourself. Background polling now pulls full threads, so these come through promptly.
- **Your refresh interval is respected at launch.** The saved refresh interval now takes effect when the app starts, instead of falling back to the default until you reopened Settings.
- **"Refresh now" during a sync no longer does nothing.** A manual refresh requested while a sync is already running is queued instead of being silently dropped.

## Notes

- PRTracker now uses conditional requests (ETags) when polling GitHub, which sharply cuts API and rate-limit usage despite the more thorough background syncing.
- The menu-bar item remains disabled in this build — PRTracker runs as a regular window for now.
- Beta housekeeping: on rare occasions this update may need to rebuild its local cache on first launch, which sends you back through repository setup. Your GitHub sign-in is preserved.
