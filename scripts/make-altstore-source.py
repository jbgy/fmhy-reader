#!/usr/bin/env python3
"""Record a built .ipa as a version in the AltStore source feed.

Reads docs/apps.json, prepends the release described by the given .ipa, and
writes the file back. Existing versions are kept so AltStore/SideStore/Feather
users can still download older builds.

Usage:
  python3 scripts/make-altstore-source.py --ipa build/FMHY.ipa \
      --repo owner/name --tag v1.0

The download URL points at the release asset named FMHY.ipa, which is what
.github/workflows/release.yml uploads.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import plistlib
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FEED = REPO_ROOT / "docs" / "apps.json"
RELEASE_ASSET = "FMHY.ipa"


def read_app_info(ipa: Path) -> dict:
    """Return Info.plist of the app bundle inside the .ipa."""
    with zipfile.ZipFile(ipa) as archive:
        plist_name = next(
            (name for name in archive.namelist()
             if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")),
            None,
        )
        if plist_name is None:
            raise SystemExit(f"error: no Payload/*.app/Info.plist inside {ipa}")
        return plistlib.loads(archive.read(plist_name))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--repo", required=True, help="GitHub repository, owner/name")
    parser.add_argument("--tag", required=True, help="Release tag, e.g. v1.0")
    parser.add_argument("--feed", type=Path, default=FEED)
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    args = parser.parse_args()

    if not args.ipa.is_file():
        raise SystemExit(f"error: {args.ipa} not found")

    info = read_app_info(args.ipa)
    version = info.get("CFBundleShortVersionString", "1.0")
    build = str(info.get("CFBundleVersion", "1"))
    minimum_os = info.get("MinimumOSVersion", "27.0")
    size = args.ipa.stat().st_size
    download_url = f"https://github.com/{args.repo}/releases/download/{args.tag}/{RELEASE_ASSET}"

    feed_path = args.feed if args.feed.is_absolute() else REPO_ROOT / args.feed
    feed = json.loads(feed_path.read_text())

    raw_base = f"https://raw.githubusercontent.com/{args.repo}/main/docs"
    feed["sourceURL"] = f"{raw_base}/apps.json"
    feed["iconURL"] = f"{raw_base}/icon.png"

    if not feed.get("apps"):
        raise SystemExit("error: apps.json has no app entry to update")

    app = feed["apps"][0]
    app["iconURL"] = f"{raw_base}/icon.png"
    app["bundleIdentifier"] = info.get("CFBundleIdentifier", app.get("bundleIdentifier"))

    entry = {
        "version": version,
        "buildVersion": build,
        "date": args.date,
        "localizedDescription": f"Release {args.tag}.",
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": minimum_os,
        "sha256": hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
    }

    versions = [v for v in app.get("versions", []) if not (
        v.get("version") == version and v.get("buildVersion") == build)]
    app["versions"] = [entry] + versions[:19]

    feed_path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    try:
        label = feed_path.relative_to(REPO_ROOT)
    except ValueError:
        label = feed_path
    print(f"==> {label}: {version} ({build}) for {minimum_os}+, {size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
