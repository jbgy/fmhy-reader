#!/usr/bin/env python3
"""Write the AltStore source feed in docs/apps.json.

Every release is its own entry in apps[], newest first. That is the layout
AltStore, SideStore and Feather use to list installable versions; an app entry
that carries a versions[] array instead makes Feather show only the newest
build, with no history.

Usage:
  # after building an .ipa
  python3 scripts/make-altstore-source.py --ipa build/FMHY.ipa \
      --repo owner/name --tag v1.5 --notes-file build/notes.txt

  # convert a feed that still uses the versions[] layout
  python3 scripts/make-altstore-source.py --migrate --repo owner/name

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
MAX_ENTRIES = 50
MAX_NEWS = 10
DISPLAY_NAME = "FMHY Reader"
DEFAULT_TINT = "#7C5CFF"


def now_iso() -> str:
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def normalise_date(value: str | None) -> str:
    """Day-only dates from older feeds become midnight UTC timestamps."""
    if not value:
        return now_iso()
    return value if "T" in value else f"{value}T00:00:00Z"


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


def asset_url(repo: str, version: str) -> str:
    return f"https://github.com/{repo}/releases/download/v{version}/{RELEASE_ASSET}"


def make_entry(
    base: dict,
    *,
    version: str,
    build: str,
    date: str,
    size: int,
    minimum_os: str,
    download_url: str,
    description: str,
    sha256: str | None,
) -> dict:
    entry = {
        "name": f"FMHY {version}",
        "bundleIdentifier": base.get("bundleIdentifier", "iOS.jbugel.fmhy"),
        "developerName": base.get("developerName", "jbgy"),
        "subtitle": f"{DISPLAY_NAME} · Build {build}",
        "localizedDescription": description,
        "iconURL": base.get("iconURL"),
        "tintColor": base.get("tintColor", DEFAULT_TINT),
        "version": version,
        "buildVersion": build,
        "versionDate": normalise_date(date),
        "downloadURL": download_url,
        "size": int(size or 0),
        "minOSVersion": minimum_os or "17.0",
    }
    if sha256:
        entry["sha256"] = sha256
    return entry


def entries_from_feed(feed: dict, repo: str) -> list[dict]:
    """Return apps[] entries in the per-version layout, converting if needed."""
    apps = feed.get("apps") or []
    if not apps:
        raise SystemExit("error: apps.json has no app entry to update")

    base = apps[0]
    entries: list[dict] = []

    if base.get("versions"):
        for version in base["versions"]:
            entries.append(
                make_entry(
                    base,
                    version=str(version["version"]),
                    build=str(version.get("buildVersion", "1")),
                    date=version.get("date", ""),
                    size=version.get("size", 0),
                    minimum_os=version.get("minOSVersion", "17.0"),
                    download_url=version.get("downloadURL") or asset_url(repo, str(version["version"])),
                    description=version.get("localizedDescription")
                    or f"Release v{version['version']}.",
                    sha256=version.get("sha256"),
                )
            )
    else:
        for app in apps:
            entries.append(
                make_entry(
                    app,
                    version=str(app["version"]),
                    build=str(app.get("buildVersion", "1")),
                    date=app.get("versionDate", ""),
                    size=app.get("size", 0),
                    minimum_os=app.get("minOSVersion", "17.0"),
                    download_url=app.get("downloadURL") or asset_url(repo, str(app["version"])),
                    description=app.get("localizedDescription", ""),
                    sha256=app.get("sha256"),
                )
            )

    entries.sort(key=lambda entry: entry["versionDate"], reverse=True)
    return entries[:MAX_ENTRIES]


def news_entry(feed: dict, app: dict, version: str, build: str, date: str, notes: str) -> dict:
    bullets = [line.lstrip("- ").strip() for line in notes.splitlines() if line.startswith("- ")]
    caption = bullets[0] if bullets else f"Build {build}"
    if len(bullets) > 1:
        caption = f"{caption} (+{len(bullets) - 1} more)"
    if len(caption) > 120:
        caption = caption[:117] + "…"
    return {
        "title": f"FMHY {version}",
        "identifier": f"{version}-{build}",
        "caption": caption,
        "date": date,
        "tintColor": app.get("tintColor", DEFAULT_TINT),
        "appID": app.get("bundleIdentifier"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ipa", type=Path, help="built .ipa to record")
    parser.add_argument("--repo", required=True, help="GitHub repository, owner/name")
    parser.add_argument("--tag", help="release tag, e.g. v1.5")
    parser.add_argument("--feed", type=Path, default=FEED)
    parser.add_argument("--notes-file", type=Path, help="plain-text release notes for this build")
    parser.add_argument("--date", default=now_iso(), help="ISO 8601 release timestamp")
    parser.add_argument("--migrate", action="store_true", help="rewrite the feed layout without adding a build")
    args = parser.parse_args()

    feed_path = args.feed if args.feed.is_absolute() else REPO_ROOT / args.feed
    feed = json.loads(feed_path.read_text())

    raw_base = f"https://raw.githubusercontent.com/{args.repo}/refs/heads/main/docs"
    feed["sourceURL"] = f"{raw_base}/apps.json"
    feed["iconURL"] = f"{raw_base}/icon.png"

    entries = entries_from_feed(feed, args.repo)
    for entry in entries:
        entry["iconURL"] = f"{raw_base}/icon.png"

    if args.migrate:
        if not args.ipa:
            feed["apps"] = entries
            feed_path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
            print(f"==> {feed_path.name}: {len(entries)} versions in the per-release layout")
            return 0

    if not args.ipa or not args.tag:
        parser.error("--ipa and --tag are required unless --migrate is given")
    if not args.ipa.is_file():
        raise SystemExit(f"error: {args.ipa} not found")

    info = read_app_info(args.ipa)
    version = str(info.get("CFBundleShortVersionString", "1.0"))
    build = str(info.get("CFBundleVersion", "1"))
    minimum_os = info.get("MinimumOSVersion", "17.0")
    size = args.ipa.stat().st_size
    url = asset_url(args.repo, version)

    notes = args.notes_file.read_text().strip() if args.notes_file and args.notes_file.is_file() else ""
    description = f"Unsigned IPA for iOS {minimum_os} and later."
    if notes:
        description = f"{notes}\n\n{description}"

    entry = make_entry(
        entries[0],
        version=version,
        build=build,
        date=args.date,
        size=size,
        minimum_os=minimum_os,
        download_url=url,
        description=description,
        sha256=hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
    )

    feed["apps"] = [entry] + [
        other for other in entries
        if not (other["version"] == version and other["buildVersion"] == build)
    ][: MAX_ENTRIES - 1]

    previous_news = [n for n in feed.get("news", []) if n.get("title") != f"FMHY {version}"]
    news = news_entry(feed, entry, version, build, normalise_date(args.date), notes)
    feed["news"] = ([news] + previous_news)[:MAX_NEWS]

    feed_path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    try:
        label = feed_path.relative_to(REPO_ROOT)
    except ValueError:
        label = feed_path
    print(f"==> {label}: {version} ({build}) for iOS {minimum_os}+, {size} bytes, {len(feed['apps'])} versions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
