# Sparkle Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship PRTracker as a signed, notarized, sandboxed macOS app that auto-updates via Sparkle 2, hosted on `oreillymedia/prtracker` GitHub Releases, starting with version 0.1.1.

**Architecture:** The app embeds Sparkle 2 via SPM and exposes a standard "Check for Updates…" command. Each release is a notarized + stapled `.app` zipped with `ditto`, uploaded as a GitHub Release asset under tag `vX.Y.Z`. A committed `appcast.xml` at the repo root, served via `raw.githubusercontent.com`, points Sparkle at the latest version. A local `scripts/release.sh` chains `xcodebuild → notarytool → stapler → ditto → generate_appcast → URL rewriter → gh release create`.

**Tech Stack:** Swift / SwiftUI, Sparkle 2 (SPM), `xcodebuild`, `xcrun notarytool` + `stapler`, Sparkle's `generate_keys` / `generate_appcast` / `sign_update` CLI tools, GitHub CLI (`gh`), Python 3 for the appcast URL rewriter.

**Spec:** `docs/superpowers/specs/2026-05-28-sparkle-distribution-design.md`

---

## Conventions used throughout this plan

- All paths are repo-relative unless prefixed with `~` or `/`.
- "The Sparkle binary tools" refers to the `bin/` directory inside Sparkle's published tarball. Task 8 installs it to `scripts/sparkle-bin/` (gitignored).
- "Login keychain" means the macOS user keychain, not the System keychain.
- For Xcode UI steps, "the PRTracker target" means the application target (not the `PRTrackerTests` target).

---

## Task 1: Bump version to 0.1.1 / build 2

**Files:**
- Modify: `PRTracker.xcodeproj/project.pbxproj` (build settings only)

- [ ] **Step 1: Open the project in Xcode**

Run: `open PRTracker.xcodeproj`

- [ ] **Step 2: Set MARKETING_VERSION on the PRTracker target**

In Xcode: PRTracker target → **Build Settings** → search for `MARKETING_VERSION` → set both Debug and Release to `0.1.1`.

(Equivalent shell-only path if preferred: `sed -i '' 's/MARKETING_VERSION = 1.0;/MARKETING_VERSION = 0.1.1;/g' PRTracker.xcodeproj/project.pbxproj` — verify only the PRTracker target's two entries change.)

- [ ] **Step 3: Set CURRENT_PROJECT_VERSION on the PRTracker target**

In Xcode: same target → **Build Settings** → search for `CURRENT_PROJECT_VERSION` → set both Debug and Release to `2`.

- [ ] **Step 4: Verify the values landed**

Run:
```bash
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" PRTracker.xcodeproj/project.pbxproj | sort -u
```

Expected output:
```
				CURRENT_PROJECT_VERSION = 2;
				MARKETING_VERSION = 0.1.1;
```

- [ ] **Step 5: Build and run the app to confirm nothing broke**

In Xcode: ⌘R. The app should launch normally; the About box (PRTracker menu → About PRTracker) should show "Version 0.1.1 (2)".

- [ ] **Step 6: Commit**

```bash
git add PRTracker.xcodeproj/project.pbxproj
git commit -m "chore(version): bump to 0.1.1 (build 2)"
```

---

## Task 2: Add Sparkle 2 SPM dependency

**Files:**
- Modify: `PRTracker.xcodeproj/project.pbxproj` (via Xcode UI)

- [ ] **Step 1: Add the package dependency**

In Xcode: **File → Add Package Dependencies…** → enter URL `https://github.com/sparkle-project/Sparkle` → **Dependency Rule:** "Up to Next Major Version" from `2.6.0` → **Add Package**.

When prompted to choose products, attach `Sparkle` to the **PRTracker** target only (not the test target).

- [ ] **Step 2: Verify the dependency landed**

Run:
```bash
grep -A1 "sparkle-project" PRTracker.xcodeproj/project.pbxproj | head -10
```

Expected: a `repositoryURL = "https://github.com/sparkle-project/Sparkle"` line and a `XCRemoteSwiftPackageReference` entry.

- [ ] **Step 3: Build to confirm SPM resolution succeeded**

In Xcode: ⌘B. Build should succeed. If it fails with "no such module 'Sparkle'", clean build folder (⇧⌘K) and retry.

- [ ] **Step 4: Commit**

```bash
git add PRTracker.xcodeproj/project.pbxproj PRTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "chore(deps): add Sparkle 2 via SPM"
```

If `Package.resolved` isn't at that path, `find PRTracker.xcodeproj -name Package.resolved` to locate it.

---

## Task 3: Install Sparkle CLI tools locally

**Files:**
- Create: `scripts/sparkle-bin/` (gitignored, contains `generate_keys`, `generate_appcast`, `sign_update`)
- Create: `.gitignore`

- [ ] **Step 1: Create a root `.gitignore`**

Create file `.gitignore` at the repo root with contents:

```gitignore
# Build artifacts
build/
releases/

# Sparkle CLI tools (downloaded per-developer; not committed)
scripts/sparkle-bin/

# macOS
.DS_Store

# Xcode user-specific state
xcuserdata/
*.xcuserstate
```

- [ ] **Step 2: Download the Sparkle release tarball**

Run:
```bash
mkdir -p scripts/sparkle-bin
cd /tmp
curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xJf sparkle.tar.xz
cp bin/generate_keys bin/generate_appcast bin/sign_update "$OLDPWD/scripts/sparkle-bin/"
cd "$OLDPWD"
```

(If a newer 2.x release is available, use that version — the script only depends on the 2.x CLI surface, which has been stable.)

- [ ] **Step 3: Verify the tools run**

Run:
```bash
./scripts/sparkle-bin/generate_appcast --help | head -3
./scripts/sparkle-bin/generate_keys --help | head -3
```

Expected: both print usage information without error.

- [ ] **Step 4: Verify the tools are gitignored**

Run:
```bash
git status --short scripts/
```

Expected: `scripts/` should not appear (it's gitignored). To confirm gitignore is doing its job:
```bash
git check-ignore -v scripts/sparkle-bin/generate_appcast
```
Expected: prints the matching `.gitignore` rule.

- [ ] **Step 5: Commit the gitignore**

```bash
git add .gitignore
git commit -m "chore: add .gitignore for build artifacts and Sparkle tools"
```

---

## Task 4: Generate EdDSA signing keys

**Files:**
- No tracked file changes; this writes a private key to the login keychain and records the public key for use in Task 5.

- [ ] **Step 1: Run generate_keys**

Run:
```bash
./scripts/sparkle-bin/generate_keys
```

Expected output: tool prints the public key (44 chars, base64) and either says "Saved new key to Keychain" or — if a Sparkle key already exists — prints the existing public key.

- [ ] **Step 2: Capture the public key**

Run:
```bash
./scripts/sparkle-bin/generate_keys -p > /tmp/sparkle-public-key.txt
cat /tmp/sparkle-public-key.txt
```

This writes the public key (just the key, no extras) to a temp file you'll paste into the project in Task 5. Do not commit this file.

- [ ] **Step 3: Verify keychain item exists**

Run:
```bash
security find-generic-password -s "https://sparkle-project.org" -a "ed25519" 2>&1 | head -5
```

Expected: prints the keychain item attributes. (`security` will exit 0; the actual secret value is not printed.)

No commit for this task — no tracked files changed.

---

## Task 5: Add Sparkle Info.plist build settings

**Files:**
- Modify: `PRTracker.xcodeproj/project.pbxproj` (build settings, via Xcode UI)

The project uses `GENERATE_INFOPLIST_FILE = YES`. Xcode injects any build setting prefixed `INFOPLIST_KEY_` into the generated Info.plist at build time. We use that mechanism for Sparkle's keys.

- [ ] **Step 1: Add INFOPLIST_KEY_SUFeedURL**

In Xcode: PRTracker target → **Build Settings** → **+ → Add User-Defined Setting** → name `INFOPLIST_KEY_SUFeedURL` → set both Debug and Release values to:

```
https://raw.githubusercontent.com/oreillymedia/prtracker/main/appcast.xml
```

- [ ] **Step 2: Add INFOPLIST_KEY_SUPublicEDKey**

Same place → **+ → Add User-Defined Setting** → name `INFOPLIST_KEY_SUPublicEDKey` → value = the public key from `/tmp/sparkle-public-key.txt` (Task 4 step 2). Set the same value for Debug and Release.

- [ ] **Step 3: Add INFOPLIST_KEY_SUEnableAutomaticChecks**

Same place → add user-defined setting `INFOPLIST_KEY_SUEnableAutomaticChecks` → value `YES` for both configurations.

- [ ] **Step 4: Add INFOPLIST_KEY_SUScheduledCheckInterval**

Same place → add user-defined setting `INFOPLIST_KEY_SUScheduledCheckInterval` → value `86400` for both configurations.

- [ ] **Step 5: Verify the four keys appear in the pbxproj**

Run:
```bash
grep -E "INFOPLIST_KEY_SU(FeedURL|PublicEDKey|EnableAutomaticChecks|ScheduledCheckInterval)" PRTracker.xcodeproj/project.pbxproj | sort -u
```

Expected: 8 lines (4 keys × 2 configurations) with the values you set.

- [ ] **Step 6: Build, then inspect the generated Info.plist**

In Xcode: ⌘B (Debug). Then:

```bash
PLIST=$(find ~/Library/Developer/Xcode/DerivedData -name Info.plist -path "*/PRTracker.app/Contents/Info.plist" -print -quit)
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST"
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST"
/usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$PLIST"
/usr/libexec/PlistBuddy -c "Print :SUScheduledCheckInterval" "$PLIST"
```

Expected: the four values you set above, with `SUEnableAutomaticChecks` shown as `true` and `SUScheduledCheckInterval` as `86400`.

- [ ] **Step 7: Commit**

```bash
git add PRTracker.xcodeproj/project.pbxproj
git commit -m "feat(sparkle): wire SUFeedURL + EdDSA public key into Info.plist"
```

---

## Task 6: Create Updater wrapper

**Files:**
- Create: `PRTracker/App/Updater.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/App/Updater.swift` with:

```swift
import Foundation
import Sparkle

@MainActor
final class Updater: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
```

- [ ] **Step 2: Add the file to the PRTracker target**

In Xcode: drag `Updater.swift` into the `App` group in the project navigator (or right-click `App` → Add Files…). Confirm target membership: **PRTracker** only, not `PRTrackerTests`.

- [ ] **Step 3: Build**

⌘B. Build should succeed.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/App/Updater.swift PRTracker.xcodeproj/project.pbxproj
git commit -m "feat(sparkle): add Updater wrapper around SPUStandardUpdaterController"
```

---

## Task 7: Wire Updater into the app + add menu item

**Files:**
- Modify: `PRTracker/App/PRTrackerApp.swift`

- [ ] **Step 1: Add stored property and init assignment**

Open `PRTracker/App/PRTrackerApp.swift`. Add `import Sparkle` after the existing imports:

```swift
import SwiftUI
import SwiftData
import Sparkle
```

Inside the struct, after `let badge = MenuBarBadge()`, add:

```swift
    @StateObject private var updater = Updater()
```

(No init change required — `@StateObject` constructs lazily on first scene access.)

- [ ] **Step 2: Add a "Check for Updates…" command to the main WindowGroup**

Replace the existing `WindowGroup` scene block:

```swift
        WindowGroup(id: "main") {
            RootView(keychain: keychain, client: client, coordinator: coordinator)
                .environment(appState)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
```

with:

```swift
        WindowGroup(id: "main") {
            RootView(keychain: keychain, client: client, coordinator: coordinator)
                .environment(appState)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
```

- [ ] **Step 3: Build**

⌘B. Build should succeed.

- [ ] **Step 4: Run the app and verify the menu item**

⌘R. In the running app's menu bar: **PRTracker → Check for Updates…** should appear directly under "About PRTracker". Clicking it will attempt to fetch the appcast — which doesn't exist on GitHub yet, so it should display "You're up to date!" or an "update check failed" dialog. Either is fine; we're only verifying the wiring.

- [ ] **Step 5: Watch for sandbox violations**

In a separate terminal, before clicking "Check for Updates…", run:

```bash
log stream --predicate 'process == "PRTracker" OR subsystem CONTAINS "sparkle"' --info
```

Click the menu item, then watch the stream for ~10 seconds. Expected: no `sandbox` denial messages, no `mach-lookup` errors mentioning Sparkle's `Installer` or `Downloader` XPC services. If any appear, consult `https://sparkle-project.org/documentation/sandboxing/` — most likely fix is adding `com.apple.security.temporary-exception.mach-lookup.global-name` entries to `PRTracker.entitlements` for the offending service. Stop the stream with ⌃C.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/App/PRTrackerApp.swift
git commit -m "feat(sparkle): add Check for Updates menu command"
```

---

## Task 8: Create release Export Options plist

**Files:**
- Create: `scripts/ExportOptions.plist`

- [ ] **Step 1: Create the directory and file**

Run:
```bash
mkdir -p scripts
```

Create `scripts/ExportOptions.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>5XJYJPRTH5</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

- [ ] **Step 2: Verify the plist parses**

Run:
```bash
plutil -lint scripts/ExportOptions.plist
```

Expected: `scripts/ExportOptions.plist: OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/ExportOptions.plist
git commit -m "build: add Developer ID export options for release"
```

---

## Task 9: Write the appcast URL rewriter (TDD)

**Files:**
- Create: `scripts/rewrite_appcast_urls.py`
- Create: `scripts/test_rewrite_appcast_urls.py`
- Test: same path as above

Sparkle's `generate_appcast` writes enclosure URLs as bare filenames (or a single prefix). We need each enclosure to point at its version's GitHub Release asset URL: `https://github.com/oreillymedia/prtracker/releases/download/v<ver>/PRTracker-<ver>.zip`.

The rewriter parses `appcast.xml`, finds each `<enclosure>` whose `url` ends with `PRTracker-X.Y.Z.zip`, and rewrites that URL to the GitHub Releases form. Versions are read from the filename, not from sibling tags (avoids dependence on `sparkle:version` or `sparkle:shortVersionString` placement).

- [ ] **Step 1: Write the failing test**

Create `scripts/test_rewrite_appcast_urls.py` with:

```python
import subprocess
import textwrap
from pathlib import Path

SCRIPT = Path(__file__).parent / "rewrite_appcast_urls.py"


def run(input_xml: str, tmp_path: Path) -> str:
    p = tmp_path / "appcast.xml"
    p.write_text(input_xml)
    subprocess.run(
        ["python3", str(SCRIPT), str(p), "--owner", "oreillymedia", "--repo", "prtracker"],
        check=True,
    )
    return p.read_text()


def test_rewrites_single_enclosure_to_github_releases_url(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <enclosure url="PRTracker-0.1.1.zip"
                         sparkle:version="2"
                         sparkle:shortVersionString="0.1.1"
                         length="123"
                         type="application/octet-stream"
                         sparkle:edSignature="abc"/>
            </item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://github.com/oreillymedia/prtracker/releases/download/v0.1.1/PRTracker-0.1.1.zip" in out
    assert 'url="PRTracker-0.1.1.zip"' not in out


def test_rewrites_url_with_existing_prefix(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <enclosure url="https://example.com/old/PRTracker-0.1.2.zip"
                         sparkle:version="3"
                         sparkle:shortVersionString="0.1.2"
                         length="456"
                         type="application/octet-stream"
                         sparkle:edSignature="def"/>
            </item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://github.com/oreillymedia/prtracker/releases/download/v0.1.2/PRTracker-0.1.2.zip" in out
    assert "example.com" not in out


def test_rewrites_multiple_items(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="PRTracker-0.1.1.zip" length="1" type="application/octet-stream" sparkle:edSignature="a"/></item>
            <item><enclosure url="PRTracker-0.1.2.zip" length="2" type="application/octet-stream" sparkle:edSignature="b"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "/v0.1.1/PRTracker-0.1.1.zip" in out
    assert "/v0.1.2/PRTracker-0.1.2.zip" in out


def test_preserves_eddsa_signature(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="PRTracker-0.1.1.zip" length="1" type="application/octet-stream" sparkle:edSignature="THESIG"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert 'sparkle:edSignature="THESIG"' in out


def test_unrecognized_filename_is_left_alone(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="https://elsewhere.example/some-other-thing.zip" length="1" type="application/octet-stream" sparkle:edSignature="x"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://elsewhere.example/some-other-thing.zip" in out
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
python3 -m pytest scripts/test_rewrite_appcast_urls.py -v
```

Expected: all 5 tests fail (script file does not yet exist; pytest will report import / file-not-found errors).

If pytest isn't available: `python3 -m pip install --user pytest` first.

- [ ] **Step 3: Write the script**

Create `scripts/rewrite_appcast_urls.py` with:

```python
#!/usr/bin/env python3
"""Rewrite Sparkle appcast enclosure URLs to GitHub Releases asset URLs.

Reads an appcast.xml in place. For each <enclosure> whose URL's basename matches
PRTracker-X.Y.Z.zip, replaces the URL with:

    https://github.com/<owner>/<repo>/releases/download/v<X.Y.Z>/PRTracker-<X.Y.Z>.zip

Enclosure URLs that don't match the expected basename pattern are left untouched.
"""

import argparse
import re
import sys
from xml.etree import ElementTree as ET

ENCLOSURE_TAG = "enclosure"
FILENAME_RE = re.compile(r"^PRTracker-(\d+\.\d+\.\d+)\.zip$")


def rewrite(tree: ET.ElementTree, owner: str, repo: str) -> int:
    rewritten = 0
    for enclosure in tree.iter(ENCLOSURE_TAG):
        url = enclosure.get("url", "")
        basename = url.rsplit("/", 1)[-1]
        match = FILENAME_RE.match(basename)
        if not match:
            continue
        version = match.group(1)
        new_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{basename}"
        enclosure.set("url", new_url)
        rewritten += 1
    return rewritten


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appcast", help="Path to appcast.xml to rewrite in place")
    parser.add_argument("--owner", required=True, help="GitHub owner / org")
    parser.add_argument("--repo", required=True, help="GitHub repo name")
    args = parser.parse_args()

    ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    tree = ET.parse(args.appcast)
    count = rewrite(tree, args.owner, args.repo)
    tree.write(args.appcast, xml_declaration=True, encoding="utf-8")
    print(f"Rewrote {count} enclosure URL(s).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Make it executable:
```bash
chmod +x scripts/rewrite_appcast_urls.py
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
python3 -m pytest scripts/test_rewrite_appcast_urls.py -v
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/rewrite_appcast_urls.py scripts/test_rewrite_appcast_urls.py
git commit -m "build: add appcast URL rewriter for GitHub Releases hosting"
```

---

## Task 10: Write the release notes template

**Files:**
- Create: `scripts/notes-template.md`

- [ ] **Step 1: Create the file**

Create `scripts/notes-template.md` with:

```markdown
# PRTracker v<VERSION>

## What's new

- _List user-visible changes here_

## Fixes

- _List bug fixes here_

## Notes

- _Anything else worth flagging (breaking changes, known issues, migration steps)_
```

- [ ] **Step 2: Commit**

```bash
git add scripts/notes-template.md
git commit -m "build: add release notes template"
```

---

## Task 11: Write the release script

**Files:**
- Create: `scripts/release.sh`

- [ ] **Step 1: Create the script**

Create `scripts/release.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 0.1.1
#
# Prerequisites (one-time, see docs/release-process.md):
#   - Developer ID Application certificate in login keychain (team 5XJYJPRTH5)
#   - Notary credentials profile "PRTracker-Notary" stored via `xcrun notarytool store-credentials`
#   - Sparkle EdDSA private key in login keychain (created by ./scripts/sparkle-bin/generate_keys)
#   - GitHub remote `origin` pointing at oreillymedia/prtracker, and `gh auth status` is happy.

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 0.1.1" >&2
    exit 64
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be in X.Y.Z form (got: $VERSION)" >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
RELEASES_DIR="$REPO_ROOT/releases"
ARCHIVE="$BUILD_DIR/PRTracker.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/PRTracker.app"
ZIP="$RELEASES_DIR/PRTracker-$VERSION.zip"
NOTES="$RELEASES_DIR/notes-$VERSION.md"
SPARKLE_BIN="$REPO_ROOT/scripts/sparkle-bin"

mkdir -p "$BUILD_DIR" "$RELEASES_DIR"

# Sanity: confirm MARKETING_VERSION in the pbxproj matches the requested version.
PROJECT_VERSION=$(grep "MARKETING_VERSION" PRTracker.xcodeproj/project.pbxproj | head -1 | awk -F'=' '{print $2}' | tr -d ' ;')
if [[ "$PROJECT_VERSION" != "$VERSION" ]]; then
    echo "MARKETING_VERSION in pbxproj is $PROJECT_VERSION but you asked to release $VERSION." >&2
    echo "Bump it (and CURRENT_PROJECT_VERSION) first, commit, then re-run." >&2
    exit 1
fi

if [[ ! -f "$NOTES" ]]; then
    echo "Missing release notes file: $NOTES" >&2
    echo "Copy scripts/notes-template.md to that path, fill it in, then re-run." >&2
    exit 1
fi

echo "==> Cleaning prior artifacts"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "==> Archiving"
xcodebuild \
    -scheme PRTracker \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    archive

echo "==> Exporting (Developer ID)"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR"

echo "==> Zipping for notarization"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notary service"
xcrun notarytool submit "$ZIP" \
    --keychain-profile PRTracker-Notary \
    --wait

echo "==> Stapling"
xcrun stapler staple "$APP"

echo "==> Re-zipping stapled .app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Generating appcast"
"$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR"

echo "==> Rewriting enclosure URLs to GitHub Releases form"
python3 scripts/rewrite_appcast_urls.py "$RELEASES_DIR/appcast.xml" \
    --owner oreillymedia --repo prtracker

echo "==> Updating committed appcast.xml"
cp "$RELEASES_DIR/appcast.xml" "$REPO_ROOT/appcast.xml"

echo "==> Done. Next steps (run manually so you can review):"
echo "    git add appcast.xml"
echo "    git commit -m 'release: v$VERSION'"
echo "    git push"
echo "    gh release create v$VERSION '$ZIP' --title 'v$VERSION' --notes-file '$NOTES'"
```

The script deliberately stops before the git push + `gh release create` so the human can eyeball the appcast diff. Those two commands are the only release-side state mutations.

Make executable:
```bash
chmod +x scripts/release.sh
```

- [ ] **Step 2: Smoke-test the script's preflight checks**

Run with bad args:
```bash
./scripts/release.sh
./scripts/release.sh 1.2
./scripts/release.sh 0.1.0  # mismatched: pbxproj says 0.1.1
```

Expected: each invocation exits non-zero with a clear error message.

Then with the correct version but no notes file:
```bash
./scripts/release.sh 0.1.1
```

Expected: exits non-zero saying "Missing release notes file: releases/notes-0.1.1.md".

- [ ] **Step 3: Commit**

```bash
git add scripts/release.sh
git commit -m "build: add Sparkle release script"
```

---

## Task 12: Write the release-process runbook

**Files:**
- Create: `docs/release-process.md`

- [ ] **Step 1: Create the file**

Create `docs/release-process.md` with:

````markdown
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

Already created during the initial Sparkle integration (see plan task 4). The private key lives in your login keychain (item name `https://sparkle-project.org`); the public key is embedded in the app's Info.plist via the `INFOPLIST_KEY_SUPublicEDKey` build setting.

#### EdDSA key custody

The private key lives in **one person's keychain**. Anyone else cutting a release must either:

1. Be given a keychain export of the private key (via Keychain Access → File → Export Items, then import on the new machine), or
2. Generate a new key, replace `INFOPLIST_KEY_SUPublicEDKey`, and cut a transitional release — but that release must be signed with the **old** key so existing users on the prior version accept the update.

For 0.1.x this is single-maintainer; revisit before adding a second releaser.

### 4. GitHub CLI

```bash
gh auth status
```

Should report you're logged in with push rights to `oreillymedia/prtracker`. If not: `gh auth login`.

### 5. Sparkle CLI tools

Download Sparkle's release tarball and extract its `bin/` to `scripts/sparkle-bin/` (gitignored). See plan task 3 for exact commands. Re-run when bumping Sparkle.

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
````

- [ ] **Step 2: Commit**

```bash
git add docs/release-process.md
git commit -m "docs: release process runbook"
```

---

## Task 13: Add GitHub remote and push

**Files:**
- No tracked file changes; configures git remote.

- [ ] **Step 1: Add the remote**

Run:
```bash
git remote add origin git@github.com:oreillymedia/prtracker.git
git remote -v
```

Expected: two lines (fetch + push) referencing `oreillymedia/prtracker`.

If you prefer HTTPS: `git remote add origin https://github.com/oreillymedia/prtracker.git`.

- [ ] **Step 2: Push main**

Run:
```bash
git push -u origin main
```

Expected: push succeeds; `main` is set as upstream.

- [ ] **Step 3: Verify on GitHub**

Run:
```bash
gh repo view oreillymedia/prtracker --web
```

Confirm the repo page shows the latest commits.

---

## Task 14: Cut release v0.1.1

**Files:**
- Create: `releases/notes-0.1.1.md` (not committed; lives only in `releases/` and on GitHub)
- Modify: `appcast.xml` (created and committed by this task)

- [ ] **Step 1: Confirm all one-time setup is done**

Run each of these and confirm output:

```bash
# Developer ID cert
security find-identity -v -p codesigning | grep "Developer ID Application.*5XJYJPRTH5"
# Expected: one line with a SHA1 prefix and "(Developer ID Application: …)"

# Notary credentials profile
xcrun notarytool history --keychain-profile PRTracker-Notary 2>&1 | head -3
# Expected: either prints recent submissions, or "No submissions found." — both confirm the profile exists.
# If it errors with "no keychain item" / "credentials not stored": run the store-credentials command from
# docs/release-process.md §1.2 before continuing.

# gh auth
gh auth status
# Expected: "Logged in to github.com" with push rights.

# Sparkle bin
ls scripts/sparkle-bin/generate_appcast scripts/sparkle-bin/sign_update
# Expected: both files exist and are executable.
```

If any of those fail, fix them per `docs/release-process.md` before proceeding. This is the only place in the plan where the human is expected to interact with Apple's notary service for credential setup — afterward, the keychain profile is permanent.

- [ ] **Step 2: Write release notes**

```bash
mkdir -p releases
cp scripts/notes-template.md releases/notes-0.1.1.md
```

Edit `releases/notes-0.1.1.md` — replace `<VERSION>` with `0.1.1` and fill in whatever's user-visible at this point. For the seed release, "Initial Sparkle-distributed build" under "Notes" is enough.

- [ ] **Step 3: Run the release pipeline**

```bash
./scripts/release.sh 0.1.1
```

Expected: script runs through archive → export → notarize (this step prints a submission UUID and waits — can take 1–10 minutes) → staple → zip → generate_appcast → rewrite_appcast_urls. Ends by printing the manual "next steps" lines.

If notarization fails, run `xcrun notarytool log <submission-uuid> --keychain-profile PRTracker-Notary` to see why; fix and re-run the script.

- [ ] **Step 4: Inspect the generated appcast**

Run:
```bash
cat appcast.xml
```

Confirm exactly one `<item>` with:
- `<title>` mentioning `0.1.1`
- `<enclosure url="https://github.com/oreillymedia/prtracker/releases/download/v0.1.1/PRTracker-0.1.1.zip" …>`
- non-empty `sparkle:edSignature`
- `sparkle:version="2"`
- `sparkle:shortVersionString="0.1.1"`

- [ ] **Step 5: Commit and push the appcast**

```bash
git add appcast.xml
git commit -m "release: v0.1.1"
git push
```

- [ ] **Step 6: Cut the GitHub Release**

```bash
gh release create v0.1.1 releases/PRTracker-0.1.1.zip \
    --title "v0.1.1" \
    --notes-file releases/notes-0.1.1.md
```

Expected: prints a URL to the release page.

- [ ] **Step 7: Verify download URL resolves**

Run:
```bash
curl -sIL https://github.com/oreillymedia/prtracker/releases/download/v0.1.1/PRTracker-0.1.1.zip \
    | grep -E "^HTTP|^content-length"
```

Expected: final `HTTP/2 200`, and a `content-length` matching the file size.

---

## Task 15: Verify auto-update path with throwaway v0.1.2

This task confirms the full Sparkle round-trip end-to-end before we declare distribution complete.

**Files:**
- Modify: `PRTracker.xcodeproj/project.pbxproj` (version bump to 0.1.2 / build 3, then bumped back)
- Create: `releases/notes-0.1.2.md`
- Modify: `appcast.xml`

- [ ] **Step 1: Install the 0.1.1 build locally**

```bash
open releases/PRTracker-0.1.1.zip
# Move the unzipped PRTracker.app to /Applications
mv ~/Downloads/PRTracker.app /Applications/  # adjust if Safari didn't unzip
```

Launch from /Applications. Confirm the app starts and Sparkle's first-launch check is satisfied (no "update available" — we're current).

Keep the running 0.1.1 process up; we'll come back to it after publishing 0.1.2.

- [ ] **Step 2: Bump versions to 0.1.2 / build 3**

In Xcode → PRTracker target → Build Settings:
- `MARKETING_VERSION` → `0.1.2` (Debug + Release)
- `CURRENT_PROJECT_VERSION` → `3` (Debug + Release)

Commit:
```bash
git add PRTracker.xcodeproj/project.pbxproj
git commit -m "chore(version): bump to 0.1.2 (build 3)"
```

- [ ] **Step 3: Write throwaway release notes**

```bash
cp scripts/notes-template.md releases/notes-0.1.2.md
```

Edit: under "Notes" write "Sparkle update path verification build."

- [ ] **Step 4: Run the release pipeline**

```bash
./scripts/release.sh 0.1.2
```

- [ ] **Step 5: Verify appcast now has two entries**

```bash
grep -E "sparkle:version=|<enclosure url=" appcast.xml
```

Expected: two enclosure URLs (v0.1.1 + v0.1.2) and two sparkle:version values (`2` and `3`).

- [ ] **Step 6: Commit, push, and cut the release**

```bash
git add appcast.xml
git commit -m "release: v0.1.2"
git push
gh release create v0.1.2 releases/PRTracker-0.1.2.zip \
    --title "v0.1.2" \
    --notes-file releases/notes-0.1.2.md
```

- [ ] **Step 7: Trigger update from running 0.1.1**

In the still-running 0.1.1 app: **PRTracker → Check for Updates…**

Expected: Sparkle pops "A new version of PRTracker is available!" naming version `0.1.2`. Click **Install Update**. Sparkle downloads the zip, verifies the EdDSA signature, replaces the app in `/Applications/`, and offers to relaunch.

After relaunch, **PRTracker → About PRTracker** should show "Version 0.1.2 (3)".

- [ ] **Step 8: Confirm sandboxing survived the update**

```bash
codesign -d --entitlements - /Applications/PRTracker.app 2>&1 | grep -E "app-sandbox|network.client"
```

Expected: both `com.apple.security.app-sandbox` and `com.apple.security.network.client` appear as `true`. (The output is the entitlements plist for the installed app.)

- [ ] **Step 9: Confirm offline launch (proves stapling worked)**

Disconnect from Wi-Fi. Launch /Applications/PRTracker.app from Finder. Expected: app launches without a Gatekeeper "verifying" delay or prompt.

Reconnect Wi-Fi.

- [ ] **Step 10: Decide whether to keep 0.1.2 in the appcast**

The 0.1.2 build was a verification artifact. Two options:

**(a) Keep it.** It's a real build; users will land on it on next check. Done.

**(b) Roll it back.** Delete the GitHub Release, remove its `<item>` from `appcast.xml`, and bump back to 0.1.1's state:

```bash
gh release delete v0.1.2 --yes
git tag -d v0.1.2 2>/dev/null || true
git push --delete origin v0.1.2 2>/dev/null || true
# Hand-edit appcast.xml to remove the 0.1.2 <item>, OR re-run generate_appcast
# after removing releases/PRTracker-0.1.2.zip and re-running the rewriter.
```

For the seed verification, **option (a) is recommended** — users who install 0.1.1 should land on the latest version anyway.

---

## Self-Review

**Spec coverage:**
- §2 Scope (in-scope items) ↔ Tasks 1 (versions), 2 (SPM), 5 (Info.plist), 6–7 (UI), 11 (script), 8 (export options), 9 (rewriter), 12 (runbook), 14 (seed release), 15 (verification). All in-scope items covered.
- §3 hosting topology ↔ Tasks 11, 14 produce the exact URL forms.
- §3 app side (Updater, commands, sandbox) ↔ Tasks 6, 7, 15 step 8.
- §3 Info.plist table ↔ Task 5.
- §3 release pipeline 9-step list ↔ Task 11's script + Task 14's runbook usage.
- §4 one-time setup ↔ Task 4 (keys), Task 12 (runbook), Task 13 (remote). Notary credential creation is documented in Task 12 (runbook) and used by Task 14; if needed before Task 14, the runbook tells the operator how.
- §5 file list ↔ all tasks combined produce every file listed.
- §6 versioning ↔ Task 1 (initial), Task 15 (verification), Task 12 (runbook).
- §7 verification plan ↔ Task 15 (1:1).
- §8 risks — bundle id quirk and EdDSA custody — surfaced in Task 12 runbook.

**Placeholder scan:** no "TBD" / "TODO" / "fill in" left. Step bodies all contain complete code or commands.

**Type / signature consistency:**
- `Updater` (Task 6) — methods `checkForUpdates()` + `canCheckForUpdates`, consumed in Task 7.
- `INFOPLIST_KEY_*` names (Task 5) — consistent in pbxproj verification grep at step 5.
- Filename pattern `PRTracker-X.Y.Z.zip` — consistent across Tasks 9, 11, 14, 15.
- Tag format `vX.Y.Z` — consistent across Tasks 11 (URL form), 14 (creation), 15 (creation).
- `PRTracker-Notary` notary profile name — consistent in Tasks 11 and 12.
