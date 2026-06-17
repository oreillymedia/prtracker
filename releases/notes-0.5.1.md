# PRTracker v0.5.1

## What's new

- **Per-PR "Last checked" time.** The detail panel now shows when each pull request was last checked, and the old "Last updated" label is now "Last activity" to make the distinction clear.
- **Updating indicator.** A spinner appears on the threads-resolved bar while a PR's details are being fetched, so you can tell when fresh data is on the way.

## Fixes

- **Clearer notifications.** Notifications no longer invent a "Someone" when the person behind a change isn't known. Push notifications now read "New commits were pushed to '…'", and state changes and ghost-author comments use neutral, personless wording instead of guessing at an identity.

## Notes

- The menu-bar item remains disabled in this build — PRTracker runs as a regular window for now.
