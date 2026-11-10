#!/usr/bin/env python3
"""Build the static site in docs/ from the release feed.

docs/apps.json is the only input: every release becomes an entry on the landing
page and a section in its month's post, for example docs/posts/nov-2026.html for
everything that shipped in November 2026.

Usage:
  python3 scripts/make-site.py           # rewrite docs/index.html and docs/posts/
  python3 scripts/make-site.py --check   # exit 1 if the committed pages are stale
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import sys
import urllib.parse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS = REPO_ROOT / "docs"
FEED = DOCS / "apps.json"
POSTS = DOCS / "posts"

SITE_TITLE = "FMHY Reader"
ACCENT = "#7C5CFF"
MONTH_SLUGS = [
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
]

CSS = """
:root {
  color-scheme: light dark;
  --accent: #7C5CFF;
  --bg: #ffffff;
  --fg: #14131a;
  --muted: #5f5d6b;
  --card: #f6f5fb;
  --line: #e4e2ee;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f0e14;
    --fg: #f2f1f7;
    --muted: #a4a1b4;
    --card: #181622;
    --line: #2a2735;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  -webkit-text-size-adjust: 100%;
}
a { color: var(--accent); }
.top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  max-width: 760px;
  margin: 0 auto;
  padding: 20px 24px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  font-weight: 650;
  color: var(--fg);
  text-decoration: none;
}
.brand img { border-radius: 8px; display: block; }
nav { display: flex; gap: 18px; font-size: 14px; }
main { max-width: 760px; margin: 0 auto; padding: 8px 24px 56px; }
.hero { text-align: center; padding: 24px 0 8px; }
.app-icon { border-radius: 22px; }
h1 { font-size: clamp(28px, 5vw, 40px); letter-spacing: -0.02em; margin: 16px 0 4px; }
h2 { font-size: 20px; margin: 0 0 10px; }
h3 {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--muted);
  margin: 18px 0 4px;
}
p { margin: 0 0 10px; }
.subtitle, .lede, .note, .meta, time { color: var(--muted); }
.subtitle { margin: 0 0 20px; }
.note { font-size: 13px; margin-top: 14px; }
.buttons { display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; }
.button {
  border: 1px solid var(--line);
  background: var(--card);
  color: var(--fg);
  padding: 10px 18px;
  border-radius: 999px;
  text-decoration: none;
  font-weight: 600;
  font-size: 15px;
}
.button.primary { background: var(--accent); border-color: var(--accent); color: #ffffff; }
.card, .release {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 16px;
  padding: 20px 22px;
  margin: 22px 0;
}
.eyebrow {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 12px;
  color: var(--muted);
  margin: 0 0 6px;
}
.lede { margin-bottom: 18px; }
ul { margin: 4px 0 0; padding-left: 20px; }
li { margin: 3px 0; }
.months { list-style: none; padding: 0; margin: 0; }
.months a {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--line);
  text-decoration: none;
  color: var(--fg);
}
.months a:hover strong { color: var(--accent); }
.months span { color: var(--muted); font-size: 14px; }
.release header {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
}
.release h2 { margin: 0; }
.release time { font-size: 14px; }
.meta { font-size: 13px; margin: 0; }
.pager { margin-top: 28px; }
footer {
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: 13px;
  text-align: center;
  padding: 24px;
}
"""


# MARK: - Feed helpers


def parse_date(value: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(
        datetime.timezone.utc
    )


def month_start(moment: datetime.datetime) -> datetime.datetime:
    return moment.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def month_slug(month: datetime.datetime) -> str:
    return f"{MONTH_SLUGS[month.month - 1]}-{month.year}"


def month_title(month: datetime.datetime) -> str:
    return f"{month.strftime('%B')} {month.year}"


def human_date(value: str) -> str:
    moment = parse_date(value)
    return f"{moment.day} {moment.strftime('%B %Y')}"


def releases_by_month(apps: list[dict]) -> list[tuple[datetime.datetime, list[dict]]]:
    groups: dict[datetime.datetime, list[dict]] = {}
    for app in apps:
        moment = month_start(parse_date(app["versionDate"]))
        groups.setdefault(moment, []).append(app)
    for entries in groups.values():
        entries.sort(key=lambda app: parse_date(app["versionDate"]), reverse=True)
    return sorted(groups.items(), reverse=True)


def repo_slug(feed: dict) -> str:
    url = (feed.get("apps") or [{}])[0].get("downloadURL", "")
    if "github.com/" in url:
        parts = url.split("github.com/", 1)[1].split("/")
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
    return "jbgy/fmhy-reader"


def altstore_add_url(feed: dict) -> str:
    source = feed.get("sourceURL") or ""
    return "https://altdirect.app/?url=" + urllib.parse.quote(source, safe="")


def plural(count: int, word: str) -> str:
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def render_notes(text: str) -> str:
    """Turn the plain feed notes (``Added:\\n- …``) into headings and lists."""
    blocks: list[str] = []
    items: list[str] = []

    def flush() -> None:
        nonlocal items
        if items:
            blocks.append("<ul>" + "".join(f"<li>{html.escape(item)}</li>" for item in items) + "</ul>")
            items = []

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.endswith(":") and len(line) <= 24:
            flush()
            blocks.append(f"<h3>{html.escape(line[:-1])}</h3>")
        elif line.startswith("- "):
            items.append(line[2:].strip())
        else:
            flush()
            blocks.append(f"<p>{html.escape(line)}</p>")
    flush()
    return "\n".join(blocks)


# MARK: - Page shell


def page(*, title: str, description: str, prefix: str, repo: str, body: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="icon" href="{prefix}icon.png">
<style>{CSS}</style>
</head>
<body>
<header class="top">
  <a class="brand" href="{prefix}index.html">
    <img src="{prefix}icon.png" alt="" width="28" height="28"> {html.escape(SITE_TITLE)}
  </a>
  <nav>
    <a href="{prefix}posts/index.html">All updates</a>
    <a href="https://github.com/{repo}">GitHub</a>
  </nav>
</header>
<main>
{body}
</main>
<footer>
  An unofficial reader for the community-maintained FMHY wiki. Not affiliated with the FMHY team.
</footer>
</body>
</html>
"""


# MARK: - Pages


def render_landing(feed: dict, months: list[tuple[datetime.datetime, list[dict]]]) -> str:
    repo = repo_slug(feed)
    latest_month, latest_apps = months[0]
    latest = latest_apps[0]
    lede = (feed.get("description") or "").split("\n\n")[0]

    month_rows = "\n".join(
        f'      <li><a href="posts/{month_slug(month)}.html">'
        f"<strong>{month_title(month)}</strong>"
        f"<span>{plural(len(entries), 'release')}</span></a></li>"
        for month, entries in months
    )

    body = f"""<section class="hero">
  <img class="app-icon" src="icon.png" alt="FMHY Reader icon" width="88" height="88">
  <h1>{html.escape(feed.get("name", SITE_TITLE))}</h1>
  <p class="subtitle">{html.escape(feed.get("subtitle", ""))}</p>
  <div class="buttons">
    <a class="button primary" href="{html.escape(altstore_add_url(feed))}">Add to AltStore</a>
    <a class="button" href="{html.escape(latest["downloadURL"])}">Download IPA</a>
    <a class="button" href="https://github.com/{repo}/releases/latest/download/FMHY-macOS.zip">macOS app</a>
  </div>
  <p class="note">iPhone, iPad and Mac · free and open source · iOS 17 and later</p>
</section>

<section class="card">
  <p class="eyebrow">Latest release · {html.escape(str(latest["version"]))}</p>
  <h2>{html.escape(latest.get("name", "FMHY"))}</h2>
  {render_notes(latest.get("localizedDescription", ""))}
  <p class="note"><a href="posts/{month_slug(latest_month)}.html">Everything from {month_title(latest_month)}</a></p>
</section>

<section>
  <h2>Every update</h2>
  <p class="lede">{html.escape(lede)}</p>
  <ul class="months">
{month_rows}
  </ul>
</section>"""

    return page(
        title=f"{SITE_TITLE} · an unofficial FMHY reader",
        description=feed.get("description", "").split("\n")[0],
        prefix="",
        repo=repo,
        body=body,
    )


def render_release(app: dict) -> str:
    version = html.escape(str(app["version"]))
    build = html.escape(str(app.get("buildVersion", "1")))
    minimum = html.escape(str(app.get("minOSVersion", "17.0")))
    return f"""  <article class="release">
    <header>
      <h2>FMHY {version}</h2>
      <time datetime="{html.escape(app["versionDate"])}">{human_date(app["versionDate"])}</time>
    </header>
    <p class="meta">Build {build} · iOS {minimum}+ ·
      <a href="{html.escape(app["downloadURL"])}">IPA</a></p>
    {render_notes(app.get("localizedDescription", ""))}
  </article>"""


def render_post(month: datetime.datetime, apps: list[dict]) -> str:
    title = month_title(month)
    releases = "\n".join(render_release(app) for app in apps)
    body = f"""<p class="eyebrow"><a href="index.html">Updates</a> · {title}</p>
<h1>{title} updates</h1>
<p class="lede">{plural(len(apps), "release")} shipped in {title}.</p>
{releases}
<p class="pager"><a href="index.html">All updates</a> · <a href="../index.html">Home</a></p>"""

    return page(
        title=f"{title} updates · {SITE_TITLE}",
        description=f"What changed in {SITE_TITLE} during {title}.",
        prefix="../",
        repo="jbgy/fmhy-reader",
        body=body,
    )


def render_posts_index(months: list[tuple[datetime.datetime, list[dict]]]) -> str:
    rows = "\n".join(
        f'    <li><a href="{month_slug(month)}.html"><strong>{month_title(month)}</strong>'
        f"<span>{plural(len(entries), 'release')}</span></a></li>"
        for month, entries in months
    )
    body = f"""<p class="eyebrow">Updates</p>
<h1>Every release, by month</h1>
<p class="lede">Short changelogs for what shipped in FMHY Reader.</p>
<ul class="months">
{rows}
</ul>"""
    return page(
        title=f"Updates · {SITE_TITLE}",
        description=f"Monthly changelogs for {SITE_TITLE}.",
        prefix="../",
        repo="jbgy/fmhy-reader",
        body=body,
    )


# MARK: - Build


def build(feed: dict) -> dict[Path, str]:
    apps = feed.get("apps") or []
    if not apps:
        raise SystemExit("error: docs/apps.json has no releases")
    months = releases_by_month(apps)
    files: dict[Path, str] = {
        DOCS / "index.html": render_landing(feed, months),
        POSTS / "index.html": render_posts_index(months),
    }
    for month, entries in months:
        files[POSTS / f"{month_slug(month)}.html"] = render_post(month, entries)
    # Keep the posts' footer/header on the same repo as the feed.
    repo = repo_slug(feed)
    for path, content in files.items():
        if path.parent == POSTS:
            files[path] = content.replace("https://github.com/jbgy/fmhy-reader", f"https://github.com/{repo}")
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the committed pages are stale")
    args = parser.parse_args()

    feed = json.loads(FEED.read_text())
    files = build(feed)
    expected = {path.name for path in files if path.parent == POSTS}
    stale = [path for path in POSTS.glob("*.html") if path.name not in expected]

    if args.check:
        missing = [
            path for path, content in files.items()
            if not path.is_file() or path.read_text() != content
        ]
        problems = sorted(path.relative_to(REPO_ROOT) for path in missing + stale)
        if problems:
            print("site is stale, run python3 scripts/make-site.py:", file=sys.stderr)
            for path in problems:
                print(f"  {path}", file=sys.stderr)
            return 1
        print(f"site ok: {len(files)} pages, {len(files) - 2} monthly posts")
        return 0

    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    for path in stale:
        path.unlink()
    print(f"==> {len(files) - 2} monthly posts and the landing page in docs/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
