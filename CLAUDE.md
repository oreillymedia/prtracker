# PRTracker

macOS menu-bar app for tracking GitHub pull requests. SwiftUI + SwiftData, distributed via Sparkle auto-update.

## Cutting a release

Full details in `docs/release-process.md`. Short version:

**1. Bump version** — in `PRTracker.xcodeproj/project.pbxproj`, update both build configurations for the PRTracker target:
- `MARKETING_VERSION` → new `X.Y.Z`
- `CURRENT_PROJECT_VERSION` → previous integer + 1

Commit: `chore(version): bump to X.Y.Z (build N)`

**2. Write release notes** — `releases/notes-X.Y.Z.md` (copy from `scripts/notes-template.md`). This directory is gitignored; only `appcast.xml` and notes files get committed back after the release.

**3. Merge and tag** — merge feature branch into `main`, tag `vX.Y.Z`.

**4. Run the release script:**
```bash
./scripts/release.sh X.Y.Z
```
This archives, exports (Developer ID), notarizes (~2–8 min), staples, re-zips, and regenerates `appcast.xml`. It prints the next steps when done.

**5. Finish up** (script prints exact commands):
```bash
git add -f releases/notes-X.Y.Z.md
git add appcast.xml
git commit -m "release: vX.Y.Z"
git push
gh release create vX.Y.Z 'releases/PRTracker-X.Y.Z.zip' --title 'vX.Y.Z' --notes-file 'releases/notes-X.Y.Z.md'
```

**Prerequisites** (one-time setup, see `docs/release-process.md`):
- Developer ID Application cert for team `5XJYJPRTH5` in login keychain
- Notary credentials stored as `PRTracker-Notary` via `xcrun notarytool store-credentials`
- Sparkle EdDSA private key in login keychain
- `scripts/sparkle-bin/` populated with Sparkle CLI tools (gitignored)
- `gh auth status` shows push access to `oreillymedia/prtracker`

## Running tests

```bash
xcodebuild -scheme PRTracker -destination 'platform=macOS' test
```
