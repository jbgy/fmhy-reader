#!/usr/bin/env python3
"""Print a stable CFBundleVersion for a release tag.

The feed's buildVersion used to be the workflow run number, which drifts
whenever a run is retried, skipped or deleted, and says nothing about the
release it belongs to. Deriving it from the tag means the number is fixed the
moment the tag exists and only ever grows between releases:

  v2.0    -> 20000
  v2.1    -> 20100
  v1.7.3  -> 10703

Usage:
  python3 scripts/build-number.py v2.0
"""

from __future__ import annotations

import argparse
import re
import sys

TAG_RE = re.compile(r"^v?(\d+)\.(\d+)(?:\.(\d+))?$")
SCALE = 100


def build_number(tag: str) -> int:
    match = TAG_RE.match(tag.strip())
    if not match:
        raise SystemExit(f"error: {tag!r} is not a release tag like v2.0")
    major, minor, patch = (int(part or 0) for part in match.groups())
    if minor >= SCALE or patch >= SCALE:
        raise SystemExit(f"error: {tag!r} needs both minor and patch below {SCALE}")
    return major * SCALE * SCALE + minor * SCALE + patch


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("tag", help="release tag, e.g. v2.0")
    args = parser.parse_args()
    print(build_number(args.tag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
