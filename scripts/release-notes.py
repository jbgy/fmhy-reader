#!/usr/bin/env python3
"""Turn the commits between two refs into release notes.

Groups conventional-commit subjects into short sections so the GitHub release
body and the source feed describe what actually changed.

Usage:
  python3 scripts/release-notes.py --from v1.4 --to v1.5 --format markdown
  python3 scripts/release-notes.py --from v1.4 --to v1.5 --format plain
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys

# Section order in the output, and the commit type that feeds each section.
SECTIONS = [
    ("feat", "Added"),
    ("fix", "Fixed"),
    ("perf", "Faster"),
    ("refactor", "Changed"),
    ("docs", "Docs"),
]
ORDER = ["Added", "Fixed", "Faster", "Changed", "Docs"]

# Release plumbing is not interesting to people installing the app.
SKIP = {"chore", "ci", "test", "style", "build"}

# Scopes that describe release plumbing rather than the app.
SKIP_SCOPES = {"release", "ci"}

SCOPES = {
    "macos": "macOS",
    "ios": "iOS",
    "feed": "Feed",
    "start": "Launch",
    "search": "Search",
}

SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?!?:\s*(?P<text>.+)$")


def git_log(start: str, end: str) -> list[str]:
    result = subprocess.run(
        ["git", "log", "--no-merges", "--reverse", "--pretty=format:%s", f"{start}..{end}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"error: git log failed: {result.stderr.strip()}")
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def headline(text: str) -> str:
    text = text.strip().rstrip(".")
    return text[0].upper() + text[1:] if text else text


def classify(subject: str) -> tuple[str, str] | None:
    match = SUBJECT.match(subject)
    if not match:
        return ("Changed", headline(subject))

    kind = match["type"]
    if kind in SKIP:
        return None

    if match["scope"] in SKIP_SCOPES:
        return None

    section = next((name for name_type, name in SECTIONS if name_type == kind), "Changed")
    text = headline(match["text"])
    if match["scope"]:
        scope = SCOPES.get(match["scope"], match["scope"])
        text = f"{scope}: {text[0].lower() + text[1:]}"
    return (section, text)


def collect(start: str, end: str) -> dict[str, list[str]]:
    buckets: dict[str, list[str]] = {name: [] for name in ORDER}
    for subject in git_log(start, end):
        entry = classify(subject)
        if entry is None:
            continue
        section, text = entry
        if text not in buckets[section]:
            buckets[section].append(text)
    if not any(buckets.values()):
        buckets["Changed"] = ["Maintenance release."]
    return buckets


def render(buckets: dict[str, list[str]], label: str, style: str) -> str:
    lines: list[str] = []
    if style == "markdown":
        lines += [f"## What's new in {label}", ""]
        for section in ORDER:
            if not buckets[section]:
                continue
            lines.append(f"### {section}")
            lines += [f"- {item}" for item in buckets[section]]
            lines.append("")
    else:
        for section in ORDER:
            if not buckets[section]:
                continue
            lines.append(f"{section}:")
            lines += [f"- {item}" for item in buckets[section]]
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from", dest="start", required=True, help="previous tag or commit")
    parser.add_argument("--to", dest="end", default="HEAD", help="release tag or commit")
    parser.add_argument("--label", help="heading for the notes; defaults to the --to ref")
    parser.add_argument("--format", choices=("markdown", "plain"), default="markdown")
    args = parser.parse_args()

    buckets = collect(args.start, args.end)
    sys.stdout.write(render(buckets, args.label or args.end, args.format))
    return 0


if __name__ == "__main__":
    sys.exit(main())
