# PRTracker v0.6.2

## Fixes

- Reconnecting now checks that your new token can actually reach your configured repositories, not just that it signs you in. If a token lacks access to a repo, the Reconnect sheet says so up front — instead of clearing the warning and then failing with "repoNotFound" on every load.

## Notes

- Nothing else worth flagging.
