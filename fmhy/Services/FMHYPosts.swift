//
//  FMHYPosts.swift
//  fmhy
//
//  FMHY publishes monthly update posts at /posts. The same posts are served as
//  an RSS feed, which is what this store downloads, turns into readable blocks
//  and caches so they open offline.
//

import Foundation
import Observation

/// One reader-friendly piece of a post. Text keeps inline markdown (links,
/// bold) so the view can route link taps through the app's own router.
struct PostBlock: Codable, Hashable {
    enum Kind: String, Codable {
        case heading
        case paragraph
        case bullet
    }

    let kind: Kind
    let text: String
}

struct FMHYPost: Identifiable, Codable, Hashable {
    let title: String
    let link: String
    let published: Date
    let blocks: [PostBlock]

    var id: String { link }

    /// First paragraph with markdown stripped, for the list row.
    var excerpt: String? {
        guard let text = blocks.first(where: { $0.kind == .paragraph })?.text else { return nil }
        return FMHYFeed.plainText(text)
    }
}

@MainActor
@Observable
final class FMHYPostsStore {
    private(set) var posts: [FMHYPost] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var lastUpdated: Date?

    private let session: URLSession
    private let cacheURL: URL
    private let cacheLifetime: TimeInterval = 6 * 60 * 60
    private var loadedHost: String?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("FMHYPosts.json")
    }

    /// Shows the cached posts immediately and only hits the network when the
    /// copy is older than the freshness window.
    func loadIfNeeded(host: String) async {
        if posts.isEmpty {
            loadCache()
        }
        if let lastUpdated,
           loadedHost == host,
           Date().timeIntervalSince(lastUpdated) < cacheLifetime {
            return
        }
        await refresh(host: host)
    }

    func refresh(host: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        for candidate in Self.hosts(startingAt: host) {
            do {
                let fetched = try await Self.fetchPosts(host: candidate, session: session)
                guard !fetched.isEmpty else { throw URLError(.cannotParseResponse) }
                posts = fetched
                loadedHost = host
                lastUpdated = .now
                error = nil
                saveCache()
                return
            } catch {
                continue
            }
        }

        if posts.isEmpty {
            self.error = "FMHY's posts couldn't be loaded. Check your connection and try again."
        }
    }

    private static func hosts(startingAt host: String) -> [String] {
        host == WikiInstances.mainID ? [host] : [host, WikiInstances.mainID]
    }

    private nonisolated static func fetchPosts(host: String, session: URLSession) async throws -> [FMHYPost] {
        guard let url = URL(string: "https://\(host)/feed.rss") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/rss+xml", forHTTPHeaderField: "Accept")
        request.setValue("FMHY-wiki-app", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try await Task.detached(priority: .userInitiated) {
            try FMHYFeed.parse(data)
        }.value
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([FMHYPost].self, from: data)
        else { return }
        posts = cached
        lastUpdated = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(posts) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

// MARK: - Parsing

enum FMHYFeed {
    static func parse(_ data: Data) throws -> [FMHYPost] {
        let parser = XMLParser(data: data)
        let delegate = FeedDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw URLError(.cannotParseResponse) }

        let posts = delegate.items.compactMap { item -> FMHYPost? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !item.html.isEmpty else { return nil }
            let body = newsBlocks(from: item.html, title: title)
            guard !body.isEmpty else { return nil }
            return FMHYPost(
                title: title,
                link: item.link,
                published: item.published ?? .distantPast,
                blocks: body
            )
        }
        return posts.sorted { $0.published > $1.published }
    }

    /// The post body without the title, date and author preamble the feed also
    /// carries: the screen shows those itself and the news starts at a heading.
    static func newsBlocks(from html: String, title: String) -> [PostBlock] {
        var blocks = blocks(from: html)
        let wanted = normalized(title)

        if let first = blocks.first, first.kind == .heading, normalized(first.text) == wanted {
            blocks.removeFirst()
        }
        if let heading = blocks.prefix(6).firstIndex(where: { $0.kind == .heading }), heading > 0 {
            blocks.removeFirst(heading)
        }
        return blocks
    }

    private static func normalized(_ text: String) -> String {
        plainText(text).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML from the feed turned into headings, paragraphs and bullets. Links and
    /// bold survive as inline markdown so `Text` can render and tap them.
    static func blocks(from html: String) -> [PostBlock] {
        var text = html
        text = replace(#"<script[\s\S]*?</script>"#, with: "", in: text)
        text = replace(#"<style[\s\S]*?</style>"#, with: "", in: text)
        text = replace(#"<a[^>]*class="header-anchor"[^>]*>[\s\S]*?</a>"#, with: "", in: text)
        text = replace(#"<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#, with: "[$2]($1)", in: text)
        text = replace(#"<(strong|b)>"#, with: "**", in: text)
        text = replace(#"</(strong|b)>"#, with: "**", in: text)
        text = replace(#"<(em|i)>"#, with: "*", in: text)
        text = replace(#"</(em|i)>"#, with: "*", in: text)
        text = replace(#"<code[^>]*>"#, with: "`", in: text)
        text = replace(#"</code>"#, with: "`", in: text)
        text = replace(#"<br[^>]*>"#, with: "\n", in: text)
        text = replace(#"<h[12][^>]*>"#, with: "\n\n## ", in: text)
        text = replace(#"<h[3-6][^>]*>"#, with: "\n\n### ", in: text)
        text = replace(#"<li[^>]*>"#, with: "• ", in: text)
        text = replace(#"</(p|div|li|h[1-6]|tr|blockquote)>"#, with: "\n\n", in: text)
        text = replace(#"<[^>]+>"#, with: "", in: text)
        text = decodeEntities(text)

        var blocks: [PostBlock] = []
        for segment in text.components(separatedBy: "\n\n") {
            let line = segment
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("### ") {
                blocks.append(PostBlock(kind: .heading, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(PostBlock(kind: .heading, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("• ") {
                blocks.append(PostBlock(kind: .bullet, text: String(line.dropFirst(2))))
            } else {
                blocks.append(PostBlock(kind: .paragraph, text: line))
            }
        }
        return blocks
    }

    /// Inline markdown removed, used for list excerpts.
    static func plainText(_ text: String) -> String {
        var plain = replace(#"\[([^\]]+)\]\([^)]*\)"#, with: "$1", in: text)
        plain = plain.replacingOccurrences(of: "**", with: "")
        plain = plain.replacingOccurrences(of: "`", with: "")
        return plain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, with template: String, in text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
            "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }

        guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else {
            return result
        }
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let codeRange = Range(match.range(at: 1), in: result)
            else { continue }
            let digits = String(result[codeRange])
            let value = digits.hasPrefix("x")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            if let value, let scalar = Unicode.Scalar(value) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return result
    }
}

/// Minimal RSS reader: the feed puts the whole post in `content:encoded`.
private final class FeedDelegate: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var published: Date?
        var html = ""
    }

    private(set) var items: [Item] = []

    private var current: Item?
    private var buffer = ""

    private static let formatters: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss zzz"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        buffer = ""
        if elementName == "item" {
            current = Item()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            buffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var item = current else { return }

        switch elementName {
        case "title":
            item.title = buffer
        case "link":
            if item.link.isEmpty { item.link = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "pubDate":
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            item.published = Self.formatters.lazy.compactMap { $0.date(from: value) }.first
        case "content:encoded":
            item.html = buffer
        case "item":
            current = nil
            if !item.title.isEmpty || !item.html.isEmpty {
                items.append(item)
            }
            return
        default:
            break
        }

        current = item
        buffer = ""
    }
}
