#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/publish.sh <version>
# Example: scripts/publish.sh 0.1.5
#
# End-to-end release: pushes pending commits, runs release.sh, commits and
# pushes the regenerated appcast, then cuts the GitHub Release. Stops only
# if a step fails. Prerequisites are the same as release.sh.

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 0.1.5" >&2
    exit 64
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be in X.Y.Z form (got: $VERSION)" >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ZIP="$REPO_ROOT/releases/PRTracker-$VERSION.zip"
NOTES="$REPO_ROOT/releases/notes-$VERSION.md"

echo "==> Pushing pending commits"
git push

echo "==> Running release.sh $VERSION"
./scripts/release.sh "$VERSION"

echo "==> Committing appcast"
git add appcast.xml
if git diff --staged --quiet; then
    echo "    No appcast changes to commit (already up to date)"
else
    git commit -m "release: v$VERSION"
    git push
fi

echo "==> Creating GitHub Release"
gh release create "v$VERSION" "$ZIP" \
    --title "v$VERSION" \
    --notes-file "$NOTES"

echo
echo "==> Done. v$VERSION is live:"
echo "    https://github.com/oreillymedia/prtracker/releases/tag/v$VERSION"
