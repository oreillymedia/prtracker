# Release Process

This document covers one-time setup and the per-release runbook for publishing PRTracker via Sparkle.

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

### 3. Run the release script

```bash
./scripts/release.sh <X.Y.Z>
```

The script archives, exports, notarizes, staples, zips, regenerates the appcast, and rewrites enclosure URLs. It stops short of pushing.

### 4. Eyeball the appcast diff

```bash
git diff appcast.xml
```

Confirm:
- A new `<item>` block exists for `X.Y.Z`
- The `<enclosure url>` points at `https://github.com/oreillymedia/prtracker/releases/download/vX.Y.Z/PRTracker-X.Y.Z.zip`
- `sparkle:edSignature` is populated (non-empty)
- `sparkle:version` matches the new `CURRENT_PROJECT_VERSION`

### 5. Push appcast + cut GitHub Release

```bash
git add appcast.xml
git commit -m "release: v<X.Y.Z>"
git push

gh release create v<X.Y.Z> releases/PRTracker-<X.Y.Z>.zip \
    --title "v<X.Y.Z>" \
    --notes-file releases/notes-<X.Y.Z>.md
```

### 6. Verify

```bash
curl -fsSL https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml \
    | grep "v<X.Y.Z>"
```

Should print the matching enclosure URL.

Open a previous build of PRTracker; use **PRTracker → Check for Updates…**. Sparkle should find the new version, verify signatures, prompt, install, and relaunch.
