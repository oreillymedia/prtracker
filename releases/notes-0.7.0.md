# PRTracker v0.7.0

## What's new

- **Private notes.** Attach a free-text note to any pull request (in the right rail) or to any conversation thread. Notes are saved locally on your Mac as you type and are never sent to GitHub.
- **Menu-bar activity notice.** The menu-bar icon switches to a "new activity" variant when a PR you care about gets activity that matches your notification settings, even if macOS notification banners are turned off. It clears when you open the popover or bring the app to the front.
- **Collapse all threads.** Comment bodies in the thread list can now be collapsed all at once.
- **Clearer token setup.** Connecting to GitHub now walks you through the exact token recipe step by step, including the SSO authorization step for `oreillymedia` that is easy to miss. Fine-grained tokens are detected and supported too.
- **Connection health check.** Connect, Reconnect, and adding a repository all run the same check of what your token can actually do: scopes, SSO authorization, repository access, and expiration. Each problem shows a plain-language explanation and, where possible, a button that fixes it.
- **Sign out actually stops.** Signing out now halts sync instead of leaving it running with no token.

## Fixes

- Connection errors use one consistent vocabulary everywhere instead of six different ones.
- Transient connection failures are no longer mistaken for a revoked token.
- Per-repository sync failures are retained and surfaced instead of being swallowed.

## Notes

- Existing tokens keep working. If the new health check flags a problem with yours, the Reconnect sheet tells you what to change.
