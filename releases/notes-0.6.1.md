# PRTracker v0.6.1

## What's new

- Expired or revoked GitHub tokens are now handled gracefully. When your token stops working, a banner appears at the top of the main window and a lightweight Reconnect sheet lets you paste a fresh token and resume — no need to re-run setup.

## Fixes

- Background syncing now pauses on an authentication failure instead of silently retrying a dead token every cycle, and resumes automatically once you reconnect.

## Notes

- Nothing else worth flagging.
