# FMHY Reader

[![CI](https://github.com/jbgy/fmhy-reader/actions/workflows/ci.yml/badge.svg)](https://github.com/jbgy/fmhy-reader/actions/workflows/ci.yml)
[![Release](https://github.com/jbgy/fmhy-reader/actions/workflows/release.yml/badge.svg)](https://github.com/jbgy/fmhy-reader/actions/workflows/release.yml)
![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20iPadOS%20%7C%20macOS-7C5CFF)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)

An unofficial, local-first reader for [FMHY](https://fmhy.net), the largest collection of free
stuff on the internet. This project is not affiliated with or endorsed by the FMHY team. Every section of the wiki is bundled with the app, so it opens instantly
and keeps working offline; the content then updates itself silently from the wiki's GitHub
repository.

## Features

- **All 26 wiki sections** in a sidebar, with a tile overview as the start screen.
- **Local-first:** a bundled snapshot is parsed on first launch, then refreshed from
  `raw.githubusercontent.com/fmhy/edit` — no API keys, no accounts, no rate-limit surprises.
- **Silent updates:** a commit feed check on launch and on foregrounding picks up changes and
  shows what is new ("New links since the last update") without an app update.
- **Search** across every section, with a breadcrumb back to the section a result came from.
- **Bookmarks** stored on device with SwiftData: folders, one-step delete, JSON export/import.
- **Cross-links** to other wiki sections and to Reddit open in the app, including anchors.
- **Tappable note links** in callouts, so a recommendation's own site is one tap away.
- **Resume:** reopening the app returns to the last section, with recently viewed sections listed.
- iPhone, iPad and Mac from one SwiftUI codebase, with light, dark and tinted icons.

## Requirements

- Xcode 27 or newer (iOS 27 / macOS 27 deployment targets).
- No Apple Developer account needed to build: the app runs in the simulator and the unsigned
  `.ipa` below is re-signed by whatever sideloader you use.

## Build and run

```bash
open fmhy.xcodeproj          # then pick the fmhy scheme
```

or from the terminal:

```bash
xcodebuild -project fmhy.xcodeproj -scheme fmhy -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project fmhy.xcodeproj -scheme fmhy -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Install on a device

Every tagged release publishes an unsigned `.ipa`, which is what AltStore, SideStore, Feather,
ESign, Sideloadly and TrollStore expect — they re-sign it with your own certificate.

**Add the source (recommended, updates automatically):**

```
https://raw.githubusercontent.com/jbgy/fmhy-reader/refs/heads/main/docs/apps.json
```

One-tap add with [AltDirect](https://altdirect.app/?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjbgy%2Ffmhy-reader%2Fmain%2Fdocs%2Fapps.json):
it offers AltStore Classic, SideStore, Feather, StikStore and TrollApps buttons. In ESign, paste
the same URL into *Sources*, or install the `.ipa` from the release page directly.

**Or build it yourself:**

```bash
./scripts/build-ipa.sh                 # build/FMHY-<version>-<build>-unsigned.ipa
./scripts/build-ipa.sh --signed TEAM   # signed with your Apple team
```

## Releasing

Pushing a tag runs the whole pipeline:

```bash
git tag v1.1 && git push origin v1.1
```

`.github/workflows/release.yml` builds the unsigned IPA with `VERSION_OVERRIDE` from the tag and
`BUILD_NUMBER_OVERRIDE` from the workflow run number, adds the version to `docs/apps.json`
(download URL, size, SHA-256, minimum OS), creates the GitHub release with `FMHY.ipa` attached,
and commits the refreshed feed back to `main` — so people who added the source get the update
through AltStore/Feather without doing anything.

`ci.yml` builds iOS and macOS on every push and pull request and validates the scripts and feed.

## How updates work

| What | Where it comes from |
| --- | --- |
| Section list and wiki content | `fmhy/edit` on GitHub (`docs/*.md`) |
| Bundled fallback snapshot | `fmhy/Resources/WikiSeed` |
| Change notification | the repository's commit Atom feed |
| Mirror list for "open in browser" | `fmhy.net/other/backups` |

The cached content lives in the app's Application Support directory and is re-parsed when the
cache format changes. If a fetch fails the app keeps the last good copy and says so instead of
showing an empty page.

## Project layout

```
fmhy/
  Models/      wiki catalog, parsed page model, link router, bookmarks
  Services/    markdown parser and the cache/update store
  Views/       overview, section pages, search, bookmarks, setup
  Resources/   bundled wiki snapshot
docs/apps.json AltStore-format source feed
scripts/       IPA packaging, AltStore feed update, icon generator
```

## Credits

Wiki content belongs to the FMHY contributors; this is just a reader for it. Not affiliated with
or endorsed by the FMHY team.
