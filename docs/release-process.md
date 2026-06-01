# Release Process

This document covers one-time setup and the per-release runbook for publishing PRTracker via Sparkle.

## How auto-update is wired

For future maintainers — three things have to be in place for in-app updates to work on a sandboxed macOS app. All three are configured today; this is documentation, not a setup checklist.

1. **`Resources/Info.plist`** carries Sparkle's runtime configuration:
   - `SUFeedURL` — appcast location
   - `SUPublicEDKey` — EdDSA public key used to verify signatures
   - `SUEnableAutomaticChecks` — background check toggle
   - `SUScheduledCheckInterval` — daily
   - **`SUEnableInstallerLauncherService = YES`** — opts into Sparkle's out-of-process installer. Without this, Sparkle tries to elevate privileges in-process and fails (`-60005 errAuthorizationDenied`) from inside the sandbox.

2. **`PRTracker/PRTracker.entitlements`** grants mach-lookup exceptions to talk to Sparkle's installer XPC services:
   ```xml
   <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
   <array>
       <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
       <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
   </array>
   ```
   `-spks` is the installer launcher service; `-spki` is the installer status service.

3. **The Sparkle SPM dependency** (currently 2.9.2) bundles the actual `Installer.xpc` and `Downloader.xpc` inside `Sparkle.framework/Versions/B/XPCServices/`. Don't touch.

If any of (1) or (2) is missing on a shipped build, that build is a permanent dead end — it cannot auto-update to a fixed version. Users on it have to manually download + replace `/Applications/PRTracker.app`. **Test the round-trip every time these change.**

## One-time setup

### 1. Developer ID Application certificate

Confirm a Developer ID Application cert for team `5XJYJPRTH5` exists in your login keychain:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

If missing: developer.apple.com → Certificates → "+" → **Developer ID Application** → follow the CSR flow in Keychain Access, then download and double-click to import.

### 2. Notary credentials

Generate an app-specific password at appleid.apple.com (Sign-In & Security → App-Specific Passwords). Then:

```bash
xcrun notarytool store-credentials PRTracker-Notary \
    --apple-id <your-apple-id> \
    --team-id 5XJYJPRTH5 \
    --password <app-specific-password>
```

This stashes the credentials in your login keychain under the profile name `PRTracker-Notary`. The release script references it by that name.

### 3. Sparkle EdDSA key

Already created during the initial Sparkle integration. The private key lives in your login keychain (item name `https://sparkle-project.org`); the public key is embedded in the app's `Resources/Info.plist`.

#### EdDSA key custody

The private key lives in **one person's keychain**. Anyone else cutting a release must either:

1. Be given a keychain export of the private key (via Keychain Access → File → Export Items, then import on the new machine), or
2. Generate a new key, replace `SUPublicEDKey` in `Resources/Info.plist`, and cut a transitional release — but that release must be signed with the **old** key so existing users on the prior version accept the update.

For 0.1.x this is single-maintainer; revisit before adding a second releaser.

### 4. GitHub CLI

```bash
gh auth status
```

Should report you're logged in with push rights to `oreillymedia/prtracker`. If not: `gh auth login`.

### 5. Sparkle CLI tools

Download Sparkle's release tarball and extract its `bin/` to `scripts/sparkle-bin/` (gitignored):

```bash
mkdir -p scripts/sparkle-bin
cd /tmp && curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-2.9.2.tar.xz
tar -xJf sparkle.tar.xz
cp bin/generate_keys bin/generate_appcast bin/sign_update \
    /Users/mblackmon/code/PRTracker/scripts/sparkle-bin/
```

Re-run when bumping the Sparkle SPM dependency to a new version.

## Per-release runbook

### 1. Bump versions

In Xcode → PRTracker target → Build Settings:

- `MARKETING_VERSION` → new X.Y.Z
- `CURRENT_PROJECT_VERSION` → previous integer + 1

Commit:
```bash
git add PRTracker.xcodeproj/project.pbxproj
git commit -m "chore(version): bump to <X.Y.Z> (build <N>)"
```

### 2. Write release notes

```bash
cp scripts/notes-template.md releases/notes-<X.Y.Z>.md
$EDITOR releases/notes-<X.Y.Z>.md
```

`releases/` is gitignored; the notes file is not committed (the GitHub Release page hosts it).

### 3. Run the full publish flow

```bash
./scripts/publish.sh <X.Y.Z>
```

`publish.sh` wraps the full pipeline: push pending commits → archive → notarize (~2-8 min) → staple → zip → regenerate appcast → commit + push appcast → cut GitHub Release. It prints the release URL on success.

If you want to inspect the appcast before publishing, use the lower-level `./scripts/release.sh <X.Y.Z>` instead — it stops short of pushing.

### 4. Verify

```bash
curl -fsSL https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml \
    | grep "v<X.Y.Z>"
```

Should print the matching enclosure URL.

Open a previous build of PRTracker; use **PRTracker → Check for Updates…**. Sparkle should find the new version, verify signatures, prompt, install, and relaunch.
