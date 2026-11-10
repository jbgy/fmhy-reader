//
//  FMHYMarkdownParser.swift
//  fmhy
//
//  Turns an FMHY wiki markdown page into categories, groups and entries.
//  The wiki is written by hand, so this is deliberately forgiving.
//

import Foundation

struct FMHYMarkdownParser {

    // MARK: - Public API

    static func parse(markdown: String, slug: String, title: String) -> WikiPage {
        var categories: [CategoryBuilder] = []

        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        func currentCategory() -> CategoryBuilder? {
            categories.isEmpty ? nil : categories[categories.count - 1]
        }

        func appendNote(_ note: String, toGroup: Bool = true) {
            let cleaned = cleanNote(note)
            guard !cleaned.isEmpty else { return }
            if let category = currentCategory() {
                if toGroup, !category.groups.isEmpty {
                    categories[categories.count - 1].groups[category.groups.count - 1].notes.append(cleaned)
                } else {
                    categories[categories.count - 1].notes.append(cleaned)
                }
            }
        }

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: "\u{200B}", with: "")
            line = line.replacingOccurrences(of: "\u{2060}", with: "")
            guard !line.isEmpty else { continue }

            // Structure separators and the "back to index" banner.
            if line.allSatisfy({ $0 == "*" || $0 == "_" }) { continue }
            if line.contains("◄◄ Back to Wiki Index") { continue }
            if line.hasPrefix("<!--") { continue }
            if line.hasPrefix("|") || line.hasPrefix("![") { continue }

            // VitePress callouts: "!!!note text".
            if line.hasPrefix("!!!") {
                var note = line.drop(while: { $0 == "!" })
                note = note.drop(while: { !$0.isWhitespace })
                appendNote(String(note).trimmingCharacters(in: .whitespaces), toGroup: false)
                continue
            }

            // Headings.
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                var heading = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)

                if level == 1 {
                    let remote = firstLink(in: heading).map {
                        WikiLink(title: cleanInline($0.title), url: $0.url)
                    }
                    heading = stripHeadingMarks(heading)
                    categories.append(
                        CategoryBuilder(
                            title: heading.isEmpty ? "Untitled" : heading,
                            remote: remote
                        )
                    )
                } else if level == 2 || level == 3 {
                    heading = stripHeadingMarks(heading)
                    guard !heading.isEmpty else { continue }
                    if categories.isEmpty {
                        categories.append(CategoryBuilder(title: title, remote: nil))
                    }
                    categories[categories.count - 1].groups.append(
                        GroupBuilder(title: heading, level: level)
                    )
                }
                continue
            }

            // Bullet entries.
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                let bullet = String(line.dropFirst(2))
                let result = parseBullet(bullet)

                if let entry = result.entry {
                    if categories.isEmpty {
                        categories.append(CategoryBuilder(title: title, remote: nil))
                    }
                    if categories[categories.count - 1].groups.isEmpty {
                        categories[categories.count - 1].groups.append(GroupBuilder(title: "", level: 2))
                    }
                    categories[categories.count - 1].groups[categories[categories.count - 1].groups.count - 1]
                        .entries.append(entry)
                } else if let note = result.note {
                    appendNote(note)
                }
                continue
            }

            // Indented continuation of the previous entry (wrap-around text).
            if rawLine.hasPrefix("  "), let last = categories.last,
               let group = last.groups.last, let entry = group.entries.last, !entry.summary.isEmpty {
                let addition = cleanInline(line)
                if !addition.isEmpty {
                    categories[categories.count - 1].groups[categories[categories.count - 1].groups.count - 1]
                        .entries[group.entries.count - 1] = WikiEntry(
                            title: entry.title,
                            url: entry.url,
                            summary: entry.summary + " " + addition,
                            kind: entry.kind,
                            extraLinks: entry.extraLinks
                        )
                }
                continue
            }

            // Free-form paragraph: context note.
            appendNote(line, toGroup: true)
        }

        let builtCategories = categories.enumerated().map { categoryIndex, builder in
            let groups = builder.groups.enumerated().map { groupIndex, group in
                WikiGroup(
                    id: "\(slug)/c\(categoryIndex)/g\(groupIndex)",
                    title: group.title,
                    level: group.level,
                    notes: group.notes,
                    entries: group.entries
                )
            }
            return WikiCategory(
                id: "\(slug)/c\(categoryIndex)",
                title: builder.title,
                remote: builder.remote,
                notes: builder.notes,
                groups: groups
            )
        }

        let useful = builtCategories.filter { !$0.groups.isEmpty || !$0.notes.isEmpty }

        return WikiPage(slug: slug, title: title, categories: useful)
    }

    // MARK: - Bullets

    private struct BulletResult {
        var entry: WikiEntry?
        var note: String?
    }

    private static let markers: [(String, WikiEntryKind)] = [
        ("⭐", .starred),
        ("🌐", .index),
        ("↪️", .crossLink),
        ("↪", .crossLink),
        ("📝", .mention),
        ("🔒", .standard),
        ("🔄", .standard),
        ("▶️", .standard),
        ("▷", .standard),
    ]

    private static func parseBullet(_ raw: String) -> BulletResult {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var kind: WikiEntryKind = .standard

        for (marker, markerKind) in markers where text.hasPrefix(marker) {
            kind = markerKind
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        // Some bullets also carry a star after a marker, e.g. "🌐 ⭐".
        if text.hasPrefix("⭐") {
            kind = .starred
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let links = extractLinks(in: text)
        let primaryLinks = links.filter { !isReferenceTitle($0.title) }

        // An entry's link must open the bullet, or be introduced by a short bold
        // label ("**Download Managers: [AB Download Manager](…)**"). Bullets that
        // merely mention a link mid-sentence stay notes.
        let leading = primaryLinks.first { isLeadingLink($0, in: text) }
        let labelled = leading == nil ? labelledLink(in: text, links: primaryLinks) : nil
        guard let primary = leading ?? labelled?.link else {
            return BulletResult(entry: nil, note: text)
        }

        let title = displayTitle(for: primary)
        let remainder = text[primary.range.upperBound...]
        var (summary, extras) = splitSummaryAndLinks(
            from: String(remainder),
            excluding: primary.url
        )
        if let label = labelled?.label {
            summary = summary.isEmpty ? label : label + " — " + summary
        }

        let entry = WikiEntry(
            title: title,
            url: primary.url,
            summary: summary,
            kind: kind,
            extraLinks: extras
        )
        return BulletResult(entry: entry, note: nil)
    }

    private static func displayTitle(for link: ParsedLink) -> String {
        let cleaned = cleanInline(link.title)
        if !cleaned.isEmpty { return cleaned }
        return link.url.host ?? link.url.absoluteString
    }

    // MARK: - Summary / extra links

    /// Splits text like `- Foo / Bar / [GitHub](url) / [Discord](url)`
    /// into a readable summary plus a list of secondary links.
    private static func splitSummaryAndLinks(
        from raw: String,
        excluding primaryURL: URL
    ) -> (String, [WikiLink]) {
        var text = raw
        // Drop the bold close marker that may directly follow the primary link.
        while text.hasPrefix("*") || text.hasPrefix(" ") {
            text.removeFirst()
        }
        if text.hasPrefix("-") {
            text.removeFirst()
            if text.hasPrefix(" ") { text.removeFirst() }
        }

        let links = extractLinks(in: text)
        guard !links.isEmpty else {
            return (cleanSummary(text), [])
        }

        var summaryParts: [String] = []
        var extras: [WikiLink] = []
        var cursor = text.startIndex

        for link in links {
            let chunk = String(text[cursor..<link.range.lowerBound])
            cursor = link.range.upperBound

            // "[2](mirror)" links are alternate mirrors, not useful rows.
            if isReferenceTitle(link.title) { continue }

            let label = cleanInline(chunk).trimmingCharacters(in: .whitespacesAndNewlines)

            if isFeatureText(label) {
                // Feature list such as "YouTube Music Client / Windows / ".
                summaryParts.append(" " + chunk)
                if let title = usableTitle(cleanInline(link.title)) {
                    extras.append(WikiLink(title: title, url: link.url))
                }
            } else if let title = usableTitle(label) ?? usableTitle(cleanInline(link.title)) {
                // Short label such as "Ad-Block Guide" or a connector like "or".
                extras.append(WikiLink(title: title, url: link.url))
            }
        }

        summaryParts.append(" " + String(text[cursor...]))

        var seen = Set<String>()
        let uniqueExtras = extras
            .filter { $0.url != primaryURL }
            .filter { seen.insert($0.id).inserted }
            .prefix(6)

        return (cleanSummary(summaryParts.joined()), Array(uniqueExtras))
    }

    /// Text before a link that reads like part of the description rather than a label.
    private static func isFeatureText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.hasSuffix("/") { return true }
        if text.count > 42 && !text.hasSuffix(",") { return true }
        return false
    }

    private static func usableTitle(_ raw: String?) -> String? {
        guard var title = raw else { return nil }
        let junk = CharacterSet(charactersIn: " -–—/·•,;:|*\n\t")
        while let first = title.first, first.unicodeScalars.allSatisfy({ junk.contains($0) }) {
            title.removeFirst()
        }
        while let last = title.last, last.unicodeScalars.allSatisfy({ junk.contains($0) }) {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let connectors: Set<String> = ["or", "and", "&", ",", "/", "+"]
        if connectors.contains(title.lowercased()) { return nil }
        guard title.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return title
    }

    /// `**Download Managers: [AB Download Manager](…)**` labels a link instead of
    /// opening with it; the label becomes the entry summary.
    private static func labelledLink(
        in text: String,
        links: [ParsedLink]
    ) -> (link: ParsedLink, label: String)? {
        guard let link = links.first else { return nil }
        var label = cleanInline(String(text[text.startIndex..<link.range.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while label.hasSuffix("*") || label.hasSuffix(" ") {
            label.removeLast()
        }
        guard label.hasSuffix(":"), label.count <= 42 else { return nil }
        label.removeLast()
        label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.contains(where: { $0.isLetter }) else { return nil }
        return (link, label)
    }

    /// True when the link opens the bullet (allowing for leading "**" or a bracket).
    private static func isLeadingLink(_ link: ParsedLink, in text: String) -> Bool {
        text.distance(from: text.startIndex, to: link.range.lowerBound) <= 3
    }

    // MARK: - Cleaning

    private static func stripHeadingMarks(_ heading: String) -> String {
        var text = heading
        // Headings sometimes contain a link: keep its label first, so the
        // marker inside the label still gets stripped below.
        if let link = firstLink(in: text) {
            text.replaceSubrange(link.range, with: link.title)
        }
        for prefix in ["► ", "►", "▷ ", "▷", "▶ ", "▶", "→ "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return cleanInline(text)
    }

    /// Notes keep their markdown links so they stay tappable in the app; bold and
    /// code markers are dropped.
    static func cleanNote(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "\u{200B}", with: "")
        text = text.replacingOccurrences(of: "\u{2060}", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanInline(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "\u{200B}", with: "")
        text = text.replacingOccurrences(of: "\u{2060}", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "<br>", with: " ")
        text = text.replacingOccurrences(of: "\\[", with: "[")
        text = text.replacingOccurrences(of: "\\]", with: "]")

        // Replace remaining markdown links with their labels.
        let links = extractLinks(in: text).reversed()
        for link in links {
            text.replaceSubrange(link.range, with: link.title)
        }
        return text
    }

    private static func cleanSummary(_ input: String) -> String {
        var text = cleanInline(input)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading/trailing separators and punctuation left behind by link removal.
        let junk = CharacterSet(charactersIn: " -–—/·•,;:|*")
        while let first = text.first, first.unicodeScalars.allSatisfy({ junk.contains($0) }) {
            text.removeFirst()
        }
        while let last = text.last, last.unicodeScalars.allSatisfy({ junk.contains($0) }) {
            text.removeLast()
        }
        // Collapse runs of separators and whitespace.
        text = text.replacingOccurrences(of: " /  / ", with: " / ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        while text.contains(" / / ") {
            text = text.replacingOccurrences(of: " / / ", with: " / ")
        }
        return text
    }

    // MARK: - Link extraction

    struct ParsedLink {
        let title: String
        let url: URL
        let range: Range<String.Index>
    }

    private static let linkRegex: NSRegularExpression = {
        let pattern = #"\[([^\[\]]*)\]\((https?://(?:[^()\s]|\([^()\s]*\))+)\)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func extractLinks(in text: String) -> [ParsedLink] {
        let nsText = text as NSString
        let matches = linkRegex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.compactMap { match in
            guard
                let titleRange = Range(match.range(at: 1), in: text),
                let urlRange = Range(match.range(at: 2), in: text),
                let fullRange = Range(match.range, in: text),
                let url = URL(string: String(text[urlRange]))
            else { return nil }
            return ParsedLink(title: String(text[titleRange]), url: url, range: fullRange)
        }
    }

    private static func firstLink(in text: String) -> ParsedLink? {
        extractLinks(in: text).first { !isReferenceTitle($0.title) }
    }

    private static func isReferenceTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isNumber }
    }
}

// MARK: - Builders

private struct CategoryBuilder {
    var title: String
    var remote: WikiLink?
    var notes: [String] = []
    var groups: [GroupBuilder] = []
}

private struct GroupBuilder {
    var title: String
    var level: Int
    var notes: [String] = []
    var entries: [WikiEntry] = []
}
