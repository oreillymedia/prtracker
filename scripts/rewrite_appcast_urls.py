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
