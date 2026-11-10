//
//  WikiModels.swift
//  fmhy
//
//  Data model for the FMHY wiki plus the static page catalog.
//

import Foundation

// MARK: - Catalog

/// A top-level wiki page. Slugs map 1:1 to `docs/<slug>.md` in github.com/fmhy/edit.
struct WikiPageDefinition: Identifiable, Hashable, Sendable {
    let slug: String
    let title: String
    let symbol: String
    let tagline: String

    var id: String { slug }
}

enum WikiCatalog {
    static let pages: [WikiPageDefinition] = [
        .init(slug: "beginners-guide", title: "Beginner's Guide", symbol: "lightbulb", tagline: "Start here"),
        .init(slug: "privacy", title: "Adblocking & Privacy", symbol: "shield.lefthalf.filled", tagline: "Block ads, trackers and worse"),
        .init(slug: "ai", title: "AI", symbol: "sparkles", tagline: "Chatbots, image and video generation"),
        .init(slug: "audio", title: "Audio", symbol: "music.note", tagline: "Streaming, radio and music tools"),
        .init(slug: "video", title: "Video", symbol: "play.tv", tagline: "Movies, shows and anime"),
        .init(slug: "video-tools", title: "Video Tools", symbol: "film", tagline: "Players, editors and utilities"),
        .init(slug: "reading", title: "Reading", symbol: "books.vertical", tagline: "Books, comics and manga"),
        .init(slug: "gaming", title: "Gaming", symbol: "gamecontroller", tagline: "Games, emulators and mods"),
        .init(slug: "gaming-tools", title: "Gaming Tools", symbol: "wrench.and.screwdriver", tagline: "Fixes, trackers and trainers"),
        .init(slug: "downloading", title: "Downloading", symbol: "arrow.down.circle", tagline: "DDL, software and media"),
        .init(slug: "torrenting", title: "Torrenting", symbol: "point.3.connected.trianglepath.dotted", tagline: "Clients and trackers"),
        .init(slug: "educational", title: "Educational", symbol: "graduationcap", tagline: "Courses, docs and research"),
        .init(slug: "storage", title: "Storage", symbol: "externaldrive", tagline: "Cloud storage and file hosts"),
        .init(slug: "file-tools", title: "File Tools", symbol: "folder", tagline: "Converters and managers"),
        .init(slug: "image-tools", title: "Image Tools", symbol: "photo", tagline: "Editors and upscalers"),
        .init(slug: "text-tools", title: "Text Tools", symbol: "textformat", tagline: "Writing, translation and OCR"),
        .init(slug: "system-tools", title: "System Tools", symbol: "gearshape", tagline: "Utilities for every OS"),
        .init(slug: "developer-tools", title: "Developer Tools", symbol: "hammer", tagline: "IDEs, APIs and learning"),
        .init(slug: "internet-tools", title: "Internet Tools", symbol: "globe", tagline: "Browsers, extensions and search"),
        .init(slug: "social-media-tools", title: "Social Media Tools", symbol: "bubble.left.and.bubble.right", tagline: "Clients, downloaders and discord"),
        .init(slug: "mobile", title: "Mobile", symbol: "iphone", tagline: "Android and iOS apps"),
        .init(slug: "linux-macos", title: "Linux & macOS", symbol: "terminal", tagline: "Apps, tips and tweaks"),
        .init(slug: "misc", title: "Misc", symbol: "square.grid.2x2", tagline: "Everything else"),
        .init(slug: "unsafe", title: "Unsafe Sites", symbol: "exclamationmark.triangle", tagline: "Sites to avoid"),
        .init(slug: "non-english", title: "Non-English", symbol: "character.bubble", tagline: "International resources"),
        .init(slug: "sandbox", title: "Sandbox", symbol: "testtube.2", tagline: "Experiments"),
    ]

    static let slugs: [String] = pages.map(\.slug)

    static let bySlug: [String: WikiPageDefinition] = Dictionary(
        uniqueKeysWithValues: pages.map { ($0.slug, $0) }
    )
}

// MARK: - Parsed content

enum WikiEntryKind: String, Codable, Sendable {
    /// A normal site entry.
    case standard
    /// ⭐ community recommendation.
    case starred
    /// 🌐 third party index.
    case index
    /// ↪️ link to another wiki section.
    case crossLink
    /// 📝 contributes to / mentions.
    case mention
}

struct WikiLink: Identifiable, Hashable, Codable, Sendable {
    let title: String
    let url: URL

    var id: String { title + "|" + url.absoluteString }
}

struct WikiEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let url: URL
    let summary: String
    let kind: WikiEntryKind
    let extraLinks: [WikiLink]

    init(title: String, url: URL, summary: String = "", kind: WikiEntryKind = .standard, extraLinks: [WikiLink] = []) {
        self.title = title
        self.url = url
        self.summary = summary
        self.kind = kind
        self.extraLinks = extraLinks
        self.id = url.absoluteString + "#" + title
    }
}

struct WikiGroup: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    /// 2 for `## ▷ ...`, 3 for `### ...`.
    let level: Int
    let notes: [String]
    let entries: [WikiEntry]

    /// Some sections are prose only (the beginner's guide), but still worth scrolling to.
    var hasContent: Bool { !entries.isEmpty || !notes.isEmpty }
}

struct WikiCategory: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let remote: WikiLink?
    let notes: [String]
    let groups: [WikiGroup]

    var entryCount: Int { groups.reduce(0) { $0 + $1.entries.count } }
}

struct WikiPage: Identifiable, Hashable, Codable, Sendable {
    let slug: String
    let title: String
    let categories: [WikiCategory]

    var id: String { slug }
    var entryCount: Int { categories.reduce(0) { $0 + $1.entryCount } }

    /// Every entry id in the page, used to diff one update against the next.
    var entryIDs: [String] {
        categories.flatMap { $0.groups }.flatMap { $0.entries }.map(\.id)
    }
}

// MARK: - Search

/// A flattened entry used by the global search screen.
struct SearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let entry: WikiEntry
    let pageSlug: String
    let pageTitle: String
    let categoryTitle: String
    let groupTitle: String
}

extension WikiPage {
    /// Resolves a wiki anchor ("► spotify tools", "android-audio") to a group.
    func groupID(matching text: String) -> String? {
        let needle = Self.normalizedAnchor(text)
        guard !needle.isEmpty else { return nil }

        // 1. Exact heading.
        for category in categories {
            for group in category.groups where group.hasContent {
                if Self.normalizedAnchor(group.title) == needle { return group.id }
            }
        }
        for category in categories where Self.normalizedAnchor(category.title) == needle {
            if let id = firstContentGroupID(in: category) { return id }
        }

        // 2. One heading contains the other.
        for category in categories {
            for group in category.groups where group.hasContent {
                let haystack = Self.normalizedAnchor(group.title)
                guard !haystack.isEmpty else { continue }
                if haystack.contains(needle) || needle.contains(haystack) { return group.id }
            }
            let title = Self.normalizedAnchor(category.title)
            guard !title.isEmpty, title.contains(needle) || needle.contains(title) else { continue }
            if let id = firstContentGroupID(in: category) { return id }
        }

        // 3. Shared words, so stale upstream anchors ("sfx loops" -> "SFX / Samples",
        // "online chatbots" -> "AI Chatbots") still land somewhere sensible.
        let words = Set(Self.anchorTokens(text)).subtracting(Self.genericHeadings)
        guard !words.isEmpty else { return nil }

        var best: (id: String, score: Int, isCategory: Bool)?
        for category in categories {
            for group in category.groups where group.hasContent {
                let score = words.intersection(Self.anchorTokens(group.title)).count
                guard score > 0 else { continue }
                if score > (best?.score ?? 0) {
                    best = (group.id, score, false)
                }
            }
            guard let id = firstContentGroupID(in: category) else { continue }
            let score = words.intersection(Self.anchorTokens(category.title)).count
            if score > (best?.score ?? 0) || (score == best?.score && score > 0) {
                best = (id, score, true)
            }
        }
        return best?.id
    }

    private func firstContentGroupID(in category: WikiCategory) -> String? {
        category.groups.first { $0.hasContent }?.id ?? category.groups.first?.id
    }

    static func normalizedAnchor(_ text: String) -> String {
        folded(text).filter { $0.isLetter || $0.isNumber }
    }

    /// Words used for loose anchor matching; short ones and generic headings are skipped.
    static func anchorTokens(_ text: String) -> [String] {
        folded(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    /// "Pokémon" and "pokemon" have to compare equal; upstream anchors drop accents.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static let genericHeadings: Set<String> = [
        "tools", "tool", "sites", "site", "apps", "app", "misc", "other",
        "more", "the", "and", "for", "guide", "guides", "list", "index",
        "resources", "general", "stuff", "sites",
    ]

    func searchItems(pageTitle: String) -> [SearchItem] {
        categories.flatMap { category in
            category.groups.flatMap { group in
                group.entries.map { entry in
                    SearchItem(
                        id: slug + "/" + entry.id,
                        entry: entry,
                        pageSlug: slug,
                        pageTitle: pageTitle,
                        categoryTitle: category.title,
                        groupTitle: group.title
                    )
                }
            }
        }
    }
}

/// Where an entry lives, needed when saving a bookmark.
struct EntryContext: Hashable, Sendable {
    let pageSlug: String
    let pageTitle: String
    let categoryTitle: String
    let groupTitle: String
}

// MARK: - Link routing

/// Recognises links that point at FMHY itself — the website or the old Reddit
/// wiki — so cross-references open the matching section inside the app.
struct WikiJump: Equatable, Sendable {
    let slug: String
    let group: String
}

enum WikiLinkRouter {
    struct Target: Equatable, Sendable {
        let slug: String
        let group: String?
    }

    /// Reddit wiki pages renamed when the wiki moved to fmhy.net. Slugs that are
    /// already catalog slugs (audio, storage, video-tools, …) pass straight through.
    private static let legacySlugs: [String: String] = [
        "adblock-vpn-privacy": "privacy",
        "dev-tools": "developer-tools",
        "torrent": "torrenting",
        "social-media": "social-media-tools",
        "android": "mobile",
        "ios": "mobile",
        "edu": "educational",
        "linux": "linux-macos",
        "game-tools": "gaming-tools",
        "games": "gaming",
        "download": "downloading",
        "non-eng": "non-english",
    ]

    /// Index pages that have no in-app counterpart; those stay in the browser.
    private static let externalOnlySlugs: Set<String> = ["index", "tools-index", "posts", "startpage"]

    static func target(for url: URL) -> Target? {
        guard let slug = sectionSlug(for: url) else { return nil }
        return Target(slug: slug, group: groupHint(from: url.fragment))
    }

    /// Turns "wiki_.25BA_spotify_tools" or "android-audio" into a group name.
    /// Reddit escapes characters as .<code point> and sometimes leaves HTML
    /// entities behind ("app_patchers_.26amp.3B_modifiers").
    private static func groupHint(from fragment: String?) -> String? {
        guard var text = fragment, !text.isEmpty else { return nil }
        if text.hasPrefix("wiki_") {
            text.removeFirst("wiki_".count)
        }

        // Reddit writes special characters as .<code point>, e.g. ".25BA" for ►.
        var decoded = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "." {
                var cursor = text.index(after: index)
                var digits = ""
                while cursor < text.endIndex, digits.count < 4, text[cursor].isHexDigit {
                    digits.append(text[cursor])
                    cursor = text.index(after: cursor)
                }
                // Prefer the 4-digit form, else the 2-digit one: ".26amp.3B" is
                // "&amp;", so the ".26" must not swallow the following "a".
                let length = digits.count >= 4 ? 4 : (digits.count >= 2 ? 2 : 0)
                if length > 0 {
                    let hex = String(digits.prefix(length))
                    let end = text.index(index, offsetBy: length + 1)
                    if let value = UInt32(hex, radix: 16),
                       (length == 4 && value >= 0x80) || (length == 2 && (0x20...0x7E).contains(value)),
                       let scalar = UnicodeScalar(value) {
                        decoded.unicodeScalars.append(scalar)
                        index = end
                        continue
                    }
                }
            }
            decoded.append(text[index])
            index = text.index(after: index)
        }

        let unescaped = decoded
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let cleaned = unescaped
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func sectionSlug(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }

        if WikiInstances.all.contains(where: { $0.host.lowercased() == host }) {
            guard parts.count == 1, let slug = parts.first else { return nil }
            return WikiCatalog.bySlug[String(slug)]?.slug
        }

        guard host == "reddit.com" || host.hasSuffix(".reddit.com"),
              parts.count >= 4,
              parts[0] == "r",
              parts[1] == "freemediaheckyeah" || parts[1] == "fmhy",
              parts[2] == "wiki"
        else { return nil }

        let slug = legacySlugs[parts[3]] ?? parts[3]
        return WikiCatalog.bySlug[slug]?.slug
    }
}
