# Sparkle Distribution — Design Spec

**Status:** Draft, awaiting user review
**Date:** 2026-05-28
**Repo:** `oreillymedia/prtracker` (public)
**First versioned release:** `0.1.1`

## 1. Goal

Ship PRTracker as a signed, notarized, sandboxed macOS app that auto-updates via Sparkle 2's standard UI. Releases are hosted on the public GitHub repo `oreillymedia/prtracker`; the appcast lives at the repo root and is served via `raw.githubusercontent.com`. A short shell script handles archive → sign → notarize → staple → zip → appcast generation → GitHub Release upload.

## 2. Scope

**In scope:**
- Sparkle 2 integration via Swift Package Manager
- `MARKETING_VERSION` bumped to `0.1.1`, `CURRENT_PROJECT_VERSION` bumped to `2`
- Standard Sparkle updater UI, daily background check, "Check for Updates…" menu item
- EdDSA appcast signing (private key in macOS keychain, public key embedded in Info.plist)
- Developer ID Application signing (team `5XJYJPRTH5`, O'Reilly) + notarization via `notarytool` + stapling
- `scripts/release.sh` driving the end-to-end release flow
- `scripts/ExportOptions.plist` for `developer-id` exports
- Generated `appcast.xml` committed at repo root
- `docs/release-process.md` runbook: one-time setup + per-release steps + EdDSA key custody note
- Verification path: cut `0.1.1` as seed, then build a throwaway `0.1.2` and confirm the running `0.1.1` finds, downloads, verifies, installs, relaunches

**Out of scope:**
- GitHub Actions / any CI automation (manual script only for 0.1.x)
- Custom SwiftUI updater UI (use Sparkle's standard windows)
- Delta updates
- Beta / preview / staged-rollout channels
- Crash reporting / telemetry integration
- Bundle identifier change away from `com.safariflow.PRTracker` (deferred; would break auto-update for users already on a prior version)
- App Store distribution

## 3. Architecture

### Hosting topology

- **Repo:** `https://github.com/oreillymedia/prtracker` — public, default branch `main`.
- **Appcast:** `appcast.xml` committed at the repo root. Sparkle fetches it from `https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml`.
- **Binaries:** each release is a GitHub Release tagged `vX.Y.Z` with one asset `PRTracker-X.Y.Z.zip` (notarized + stapled `.app` zipped via `ditto -c -k --keepParent`).
- **Enclosure URLs in appcast:** `https://github.com/oreillymedia/prtracker/releases/download/vX.Y.Z/PRTracker-X.Y.Z.zip` (the canonical GitHub Releases asset URL; emitted by `generate_appcast` automatically when given the local zip).

### App side

- Sparkle 2 added as an SPM dependency, attached to the `PRTracker` target.
- A single new file, `PRTracker/App/Updater.swift`, holds a thin `ObservableObject` wrapping `SPUStandardUpdaterController`. The controller starts the updater at init (`startingUpdater: true`).
- `PRTracker/App/PRTrackerApp.swift` instantiates `Updater` once at scene root and adds a `CommandGroup(after: .appInfo)` containing a "Check for Updates…" button bound to `controller.checkForUpdates(_:)`.
- The app stays sandboxed. Sparkle's SPM artifact bundles the Installer/Downloader XPC services it needs; no entitlement changes are expected beyond the current `com.apple.security.app-sandbox` + `com.apple.security.network.client`. If Sparkle's sandboxing guide surfaces additional `mach-lookup` temporary-exception entitlements during integration, those go into `PRTracker.entitlements` per its docs.

### Info.plist keys

Added via the target's "Info.plist Values" build settings (the project uses generated-Info.plist style; no standalone Info.plist file is checked in today):

| Key | Value |
| --- | --- |
| `SUFeedURL` | `https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml` |
| `SUPublicEDKey` | (the EdDSA public key emitted by Sparkle's `generate_keys`) |
| `SUEnableAutomaticChecks` | `YES` |
| `SUScheduledCheckInterval` | `86400` (daily) |

### Release pipeline

`scripts/release.sh <version>` performs the following steps, failing fast on any error:

1. `xcodebuild -scheme PRTracker -configuration Release -archivePath build/PRTracker.xcarchive archive`
2. `xcodebuild -exportArchive -archivePath build/PRTracker.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export` (method: `developer-id`, automatic signing, team `5XJYJPRTH5`)
3. `ditto -c -k --keepParent build/export/PRTracker.app releases/PRTracker-<v>.zip`
4. `xcrun notarytool submit releases/PRTracker-<v>.zip --wait --keychain-profile PRTracker-Notary`
5. `xcrun stapler staple build/export/PRTracker.app`
6. Re-zip the stapled `.app` to `releases/PRTracker-<v>.zip` (overwrite) so the ticket travels with the binary
7. `generate_appcast releases/` (Sparkle tool — produces/updates `releases/appcast.xml`, signing each entry with the EdDSA private key in the keychain)
8. Rewrite each `<enclosure url>` in `releases/appcast.xml` from the default file-name URL to the GitHub Releases asset URL for that version. Concretely: a small `scripts/rewrite-appcast-urls.py` (or `sed -E`) walks the file and maps `…/PRTracker-X.Y.Z.zip` → `https://github.com/oreillymedia/prtracker/releases/download/vX.Y.Z/PRTracker-X.Y.Z.zip`. This preserves all historical entries when re-running per release.
9. `cp releases/appcast.xml ./appcast.xml`; git add, commit, push
10. `gh release create v<v> releases/PRTracker-<v>.zip --title "v<v>" --notes-file releases/notes-<v>.md`

`releases/` is in `.gitignore` (binaries are not committed); only the generated `appcast.xml` is committed back at the repo root.

`scripts/ExportOptions.plist` is a small plist with `method=developer-id`, `signingStyle=automatic`, `teamID=5XJYJPRTH5`, `destination=export`.

## 4. One-time setup (documented in `docs/release-process.md`)

1. Confirm a Developer ID Application certificate for team `5XJYJPRTH5` exists in the login keychain (`security find-identity -v -p codesigning`). If missing, create via Apple Developer → Certificates.
2. Create notary credentials profile: `xcrun notarytool store-credentials PRTracker-Notary --apple-id <apple-id> --team-id 5XJYJPRTH5 --password <app-specific-password>`.
3. Run Sparkle's `generate_keys` once. The private EdDSA key is stored in the login keychain (item name `https://sparkle-project.org`); copy the public key it prints into the `SUPublicEDKey` Info.plist build setting.
4. Add the GitHub remote and push: `git remote add origin git@github.com:oreillymedia/prtracker.git && git push -u origin main`.

### EdDSA key custody

The EdDSA private key lives in Matt's login keychain. Anyone else cutting a release must either (a) be given a keychain export of the private key, or (b) use a different signing key — in which case the new public key must replace `SUPublicEDKey` in a new release, and *that* release must be signed with the old key so users on the current build accept the update. For 0.1.x this is single-maintainer; revisit before adding a second releaser.

## 5. Project changes (files touched)

- `PRTracker.xcodeproj/project.pbxproj`
  - `MARKETING_VERSION = 0.1.1` (Debug + Release)
  - `CURRENT_PROJECT_VERSION = 2` (Debug + Release)
  - Sparkle SPM dependency added
  - Four Info.plist values added (see table in §3)
- `PRTracker/App/Updater.swift` *(new)* — `SPUStandardUpdaterController` wrapper
- `PRTracker/App/PRTrackerApp.swift` — own an `Updater`; add `CommandGroup(after: .appInfo)` with "Check for Updates…"
- `scripts/release.sh` *(new)*
- `scripts/ExportOptions.plist` *(new)*
- `scripts/rewrite-appcast-urls.py` *(new)* — rewrites enclosure URLs to GitHub Releases paths
- `scripts/notes-template.md` *(new, optional)* — release-notes skeleton
- `appcast.xml` *(new, generated, committed)*
- `docs/release-process.md` *(new)* — setup + runbook + key custody
- `.gitignore` — add `build/` and `releases/`
- `PRTracker.entitlements` — unchanged unless Sparkle's sandboxing guide requires additions during integration

## 6. Versioning

- `MARKETING_VERSION` is the user-visible version (`0.1.1`, `0.1.2`, …). Set per release.
- `CURRENT_PROJECT_VERSION` (= `CFBundleVersion`) is what Sparkle compares for update detection. It increments **monotonically per release**, independent of marketing version (`1` is the pre-Sparkle local-only build; the first Sparkle release is `2`; the test release in §7 is `3`; …).
- The appcast's `<sparkle:version>` for each entry uses `CFBundleVersion`; `<sparkle:shortVersionString>` uses the marketing version. `generate_appcast` reads both from the zipped `.app` automatically.

## 7. Verification plan

1. Build and ship `0.1.1` (marketing `0.1.1`, bundle version `2`) via the full pipeline — this seeds the appcast.
2. Install the `0.1.1` zip on a clean Mac (or fresh user account) and launch.
3. Build a throwaway `0.1.2` (marketing `0.1.2`, bundle version `3`) via the same pipeline and publish it.
4. With `0.1.1` running, choose "Check for Updates…" — Sparkle should find `0.1.2`, verify EdDSA + Developer ID signatures + notarization ticket, prompt, install, and relaunch.
5. Confirm post-update: app is still sandboxed (`codesign -d --entitlements - /Applications/PRTracker.app` shows `app-sandbox`), launches without Gatekeeper prompts offline (proves stapling), and the updater menu item is still wired.
6. Confirm appcast.xml renders correctly via `curl https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml`.

## 8. Risks / open questions

- **Sandbox + Sparkle integration gotchas:** Sparkle 2 sandboxed apps occasionally need `com.apple.security.temporary-exception.mach-lookup.global-name` entitlements for the bundled XPC services. The exact list, if any, is determined during implementation by following Sparkle's `Documentation/Sandboxing.md`. Plan accommodates adding them.
- **Bundle id quirk:** `com.safariflow.PRTracker` signed under O'Reilly's team is stylistically odd. Changing it after `0.1.1` ships would orphan early users from auto-update (Sparkle's "bundle id changed" path requires a custom dance). Decision deferred to pre-1.0.
- **EdDSA key on a single laptop:** documented above; acceptable for now, blocking only if a second releaser appears.
- **`generate_appcast` doesn't natively know about GitHub Releases per-tag paths.** Hence the URL-rewrite step. If we later move to GitHub Pages or a single-bucket layout where every zip lives under one stable prefix, we can drop the rewriter and use `--download-url-prefix` instead.
- **No release notes pipeline yet:** the script accepts `--notes-file` but no convention is set for where release-note prose comes from (PR descriptions? hand-written? generated?). For 0.1.1, hand-written into `releases/notes-0.1.1.md`.
