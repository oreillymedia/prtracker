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
"$SPARKLE_BIN/generate_appcast" --maximum-deltas 0 "$RELEASES_DIR"

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
