# PRTracker v0.4.0

## What's new

- **Track multiple repositories at once.** A new **Repositories** tab in Settings lets you add, enable/disable, and remove the repos you watch — laid out like Mail's accounts, with a detail panel for each repo.
- **Per-repository notifications.** Each repository has its own notification level — Everything, Personal, or None — so you can go all-in on the repo you own and stay quiet on the noisy ones, independently.
- **Quick repository switcher.** The bottom of the sidebar now shows how many repositories are active; click it to flip individual repos on or off without losing any data, or jump straight to Manage Repositories.
- **Repository shown in the detail view.** The pull-request header and the info panel now show which repository a PR belongs to, and the source list merges open PRs across all your active repositories.
- An at-a-glance summary now fills the detail pane when no pull request is selected.

## Fixes

- Adding a repository no longer triggers a burst of notifications for its already-open pull requests — only activity from that point on notifies.
- More resilient local data handling: a transient failure opening the local store is retried instead of discarding data.

## Notes

- Disabling a repository keeps all of its stored data; it simply stops appearing in the list and sending notifications until you turn it back on.
- The menu-bar item remains disabled in this build — PRTracker runs as a regular window for now.
