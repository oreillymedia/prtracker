# Sparkle Distribution — Design Spec

**Status:** Shipped (verified end-to-end at v0.1.5 → v0.1.6 on 2026-06-01)
**Date:** 2026-05-28; updated 2026-06-01 to reflect shipped reality
**Repo:** `oreillymedia/prtracker` (public)
**First versioned release:** `0.1.1` (first version with working auto-update: `0.1.5`)

## 1. Goal

Ship PRTracker as a signed, notarized, sandboxed macOS app that auto-updates via Sparkle 2's standard UI. Releases are hosted on the public GitHub repo `oreillymedia/prtracker`; the appcast lives at the repo root and is served via `raw.githubusercontent.com`. A pair of shell scripts (`release.sh` for build, `publish.sh` for the full publish flow) handles archive → sign → notarize → staple → zip → appcast generation → GitHub Release upload.

## 2. Scope

**In scope:**
- Sparkle 2 integration via Swift Package Manager (resolved to 2.9.2)
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumps
- Standard Sparkle updater UI, daily background check, "Check for Updates…" menu item
- EdDSA appcast signing (private key in macOS keychain, public key embedded in Info.plist)
- Developer ID Application signing (team `5XJYJPRTH5`, O'Reilly) + notarization via `notarytool` + stapling
- Sandboxed installer wired via Sparkle's out-of-process installer launcher service
- `scripts/release.sh` driving the build pipeline; `scripts/publish.sh` wrapping the full publish flow
- `scripts/ExportOptions.plist` for `developer-id` exports
- `scripts/rewrite_appcast_urls.py` (with pytest coverage) post-processing appcast URLs to GitHub Release asset paths
- Generated `appcast.xml` committed at repo root
- `docs/release-process.md` runbook
- Verification path: build a throwaway `vX.Y+1` from a known-good install and confirm in-app auto-update succeeds

**Out of scope:**
- GitHub Actions / any CI automation (manual scripts only for 0.1.x)
- Custom SwiftUI updater UI (use Sparkle's standard windows)
- Delta updates (explicitly disabled via `--maximum-deltas 0` — generate_appcast would otherwise emit delta enclosure URLs we don't host)
- Beta / preview / staged-rollout channels
- Crash reporting / telemetry integration
- Bundle identifier change away from `com.safariflow.PRTracker` (deferred; would break auto-update for users already on a prior version)
- App Store distribution

## 3. Architecture

### Hosting topology

- **Repo:** `https://github.com/oreillymedia/prtracker` — public, default branch `main`.
- **Appcast:** `appcast.xml` committed at the repo root. Sparkle fetches it from `https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml`.
- **Binaries:** each release is a GitHub Release tagged `vX.Y.Z` with one asset `PRTracker-X.Y.Z.zip` (notarized + stapled `.app` zipped via `ditto -c -k --keepParent`).
- **Enclosure URLs in appcast:** `https://github.com/oreillymedia/prtracker/releases/download/vX.Y.Z/PRTracker-X.Y.Z.zip`. `generate_appcast` emits bare filenames; a Python post-process rewrites them to the GitHub Release form.

### App side

- Sparkle 2 added as an SPM dependency, attached to the `PRTracker` target.
- `PRTracker/App/Updater.swift` holds a thin `@MainActor @Observable final class` wrapping `SPUStandardUpdaterController` (Swift 6 + Xcode 26 forced this away from the plan's original `ObservableObject` + `@StateObject` pattern — `@MainActor` classes can't conform to `ObservableObject`).
- `PRTracker/App/PRTrackerApp.swift` instantiates `Updater` once at scene root and adds a `CommandGroup(after: .appInfo)` containing a "Check for Updates…" button bound to `controller.checkForUpdates(_:)`.

### Sandbox configuration (the hard-won part)

A sandboxed app cannot elevate privileges in-process for the installer step. Three pieces must all be present, or auto-update fails with `AuthorizationCopyRights` returning `-60005` and Sparkle reporting "Failed to gain authorization required to update target":

1. **`Resources/Info.plist`** must set `SUEnableInstallerLauncherService = YES`. This is the opt-in to Sparkle's out-of-process installer; without it, Sparkle defaults to the in-process path which the sandbox forbids.
2. **`PRTracker/PRTracker.entitlements`** must include mach-lookup temporary exceptions for the installer's mach service names:
   ```xml
   <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
   <array>
       <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
       <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
   </array>
   ```
   `-spks` is the installer launcher service; `-spki` is the installer status service.
3. The Sparkle SPM dependency bundles the actual XPC services (`Installer.xpc`, `Downloader.xpc`) inside the framework — no manual copy step needed.

Any build that ships without (1) or (2) is a **permanent dead end** for auto-update: it cannot install any future version. Versions 0.1.1 through 0.1.4 shipped with these issues and required manual install of 0.1.5 to recover.

### Info.plist keys (Resources/Info.plist)

The project uses `GENERATE_INFOPLIST_FILE = YES`, but Xcode 26's build system only injects `INFOPLIST_KEY_*` build settings for *registered* keys; arbitrary Sparkle keys are silently dropped. The workaround is a supplemental `Resources/Info.plist` (referenced via `INFOPLIST_FILE`) that Xcode merges with the generated plist at build time:

| Key | Value |
| --- | --- |
| `SUFeedURL` | `https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key from Sparkle's `generate_keys` |
| `SUEnableAutomaticChecks` | `true` |
| `SUScheduledCheckInterval` | `86400` (daily) |
| `SUEnableInstallerLauncherService` | `true` |

`Resources/Info.plist` lives outside `PRTracker/` because the file-system-synchronized group would otherwise auto-include it in the Copy Bundle Resources phase, duplicating the plist in the .app bundle.

### Release pipeline

`scripts/release.sh <version>` performs the following, failing fast on any error:

1. `xcodebuild -scheme PRTracker -configuration Release -archivePath build/PRTracker.xcarchive archive`
2. `xcodebuild -exportArchive -archivePath build/PRTracker.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export` (method: `developer-id`, automatic signing, team `5XJYJPRTH5`)
3. `ditto -c -k --keepParent build/export/PRTracker.app releases/PRTracker-<v>.zip`
4. `xcrun notarytool submit releases/PRTracker-<v>.zip --wait --keychain-profile PRTracker-Notary`
5. `xcrun stapler staple build/export/PRTracker.app`
6. Re-zip the stapled `.app` to `releases/PRTracker-<v>.zip` so the ticket travels with the binary
7. `generate_appcast --maximum-deltas 0 releases/` (deltas explicitly disabled — see Scope)
8. `python3 scripts/rewrite_appcast_urls.py releases/appcast.xml --owner oreillymedia --repo prtracker` — maps each `PRTracker-X.Y.Z.zip` enclosure to `https://github.com/oreillymedia/prtracker/releases/download/vX.Y.Z/PRTracker-X.Y.Z.zip`
9. `cp releases/appcast.xml ./appcast.xml`

`scripts/publish.sh <version>` wraps `release.sh` and adds: `git push` of pending commits, commit + push of `appcast.xml`, and `gh release create`. End-to-end one-command publish.

`releases/` is in `.gitignore` (binaries not committed); only the generated `appcast.xml` is committed at the repo root.

## 4. One-time setup (documented in `docs/release-process.md`)

1. Confirm a Developer ID Application certificate for team `5XJYJPRTH5` exists in the login keychain.
2. Create notary credentials profile: `xcrun notarytool store-credentials PRTracker-Notary --apple-id <apple-id> --team-id 5XJYJPRTH5 --password <app-specific-password>`.
3. Run Sparkle's `generate_keys` once. The private EdDSA key is stored in the login keychain (item name `https://sparkle-project.org`); copy the public key into `Resources/Info.plist`'s `SUPublicEDKey`.
4. Add the GitHub remote and push.

### EdDSA key custody

The EdDSA private key lives in Matt's login keychain. Anyone else cutting a release must either (a) be given a keychain export of the private key, or (b) use a different signing key — in which case the new public key must replace `SUPublicEDKey` in a new release, and *that* release must be signed with the old key so users on the current build accept the update. For 0.1.x this is single-maintainer; revisit before adding a second releaser.

## 5. Project changes (files touched)

- `PRTracker.xcodeproj/project.pbxproj` — version bumps; Sparkle SPM dep; `INFOPLIST_FILE = Resources/Info.plist`
- `PRTracker/App/Updater.swift` *(new)* — `@MainActor @Observable` wrapper around `SPUStandardUpdaterController`
- `PRTracker/App/PRTrackerApp.swift` — owns the `Updater`; adds `CommandGroup(after: .appInfo)` with "Check for Updates…"
- `PRTracker/PRTracker.entitlements` — adds `mach-lookup` temporary exceptions for `-spks` and `-spki`
- `Resources/Info.plist` *(new)* — supplemental plist with the SU* keys
- `appcast.xml` *(new, generated, committed)*
- `scripts/release.sh` *(new)*
- `scripts/publish.sh` *(new)* — wraps release.sh + push + gh release create
- `scripts/ExportOptions.plist` *(new)*
- `scripts/rewrite_appcast_urls.py` *(new)* — rewrites enclosure URLs to GitHub Releases paths
- `scripts/test_rewrite_appcast_urls.py` *(new)* — pytest coverage
- `scripts/notes-template.md` *(new)* — release-notes skeleton
- `docs/release-process.md` *(new)* — setup + runbook + key custody + sandbox notes
- `.gitignore` — adds `build/`, `releases/`, `scripts/sparkle-bin/`, `scripts/__pycache__/`, etc.

## 6. Versioning

- `MARKETING_VERSION` is the user-visible version (`0.1.1`, `0.1.2`, …). Set per release.
- `CURRENT_PROJECT_VERSION` (= `CFBundleVersion`) is what Sparkle compares for update detection. It increments **monotonically per release**, independent of marketing version (`1` is the pre-Sparkle local-only build; the first Sparkle release is `2`; each subsequent release adds 1).
- The appcast's `<sparkle:version>` for each entry uses `CFBundleVersion`; `<sparkle:shortVersionString>` uses the marketing version. `generate_appcast` reads both from the zipped `.app` automatically.

## 7. Verification plan (as executed)

1. Built and shipped `0.1.1` (bundle 2) via the full pipeline — seeded the appcast. *(In retrospect, 0.1.1 was a dead end: missing the launcher service key + mach-lookup entitlements.)*
2. Built `0.1.2` (bundle 3) and attempted in-app update from running 0.1.1 → failed with `-60005` because of (a) above.
3. Added mach-lookup entitlements → shipped `0.1.3` (bundle 4); installed manually. Still failed.
4. Added `SUEnableInstallerLauncherService = YES` to Info.plist → shipped `0.1.5` (bundle 6); installed manually.
5. Built throwaway `0.1.6` (bundle 7) and triggered "Check for Updates…" from running 0.1.5. **Sparkle found, verified, installed, and relaunched cleanly.** ✅
6. Post-update verification: `codesign -d --entitlements -` confirmed sandbox + entitlements survived; `xcrun stapler validate` confirmed the notary ticket is stapled.

The lesson worth carrying forward: **the first release everyone installs becomes a permanent baseline** for what auto-update can fix. Anything missing in that first build requires a manual install to recover. Test the round-trip with a throwaway release before the first install reaches anyone who isn't you.

## 8. Risks / lessons learned

- **Sandboxed Sparkle setup is non-obvious.** The plan assumed minimal entitlement changes; reality required both `SUEnableInstallerLauncherService=YES` and explicit `mach-lookup` exceptions. The Sparkle docs cover this but the SPM distribution doesn't surface it. Future-proofing: `docs/release-process.md` now leads with these requirements.
- **Xcode 26's `INFOPLIST_KEY_*` injection is selective.** Only registered keys land in the generated plist; arbitrary Sparkle keys are silently dropped. Supplemental Info.plist via `INFOPLIST_FILE` is the workaround.
- **`generate_appcast` emits delta URLs by default.** Without `--maximum-deltas 0`, the appcast points at non-existent `.delta` files on raw.githubusercontent.com, causing Sparkle to 404 before falling back to the full enclosure. Cosmetically broken; eventually fixed mid-stream.
- **Bundle id quirk:** `com.safariflow.PRTracker` signed under O'Reilly's team is stylistically odd. Changing it after shipped releases would orphan early users from auto-update. Decision deferred to pre-1.0.
- **EdDSA key on a single laptop:** acceptable for now, blocking only if a second releaser appears.
