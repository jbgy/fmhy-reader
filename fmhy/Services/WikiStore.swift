//
//  WikiStore.swift
//  fmhy
//
//  Local-first wiki store: bundled seed -> on-disk cache -> silent OTA updates.
//

import Foundation
import Observation

@MainActor
@Observable
final class WikiStore {

    enum Connection: Equatable {
        case unknown
        case online
        case offline
    }

    // MARK: - Public state

    let catalog: [WikiPageDefinition] = WikiCatalog.pages

    private(set) var pages: [String: WikiPage] = [:]
    /// The links the loaded pages hold right now, keyed by slug. The bookmark
    /// audit compares saved links against this to notice ones the wiki dropped.
    private(set) var liveURLs: [String: Set<String>] = [:]
    private(set) var loadingSlugs: Set<String> = []
    private(set) var failedSlugs: Set<String> = []
    private(set) var searchIndex: [SearchItem] = []
    private(set) var lastUpdated: Date?
    private(set) var lastCommitDate: Date?
    private(set) var isRefreshing = false
    private(set) var connection: Connection = .unknown
    private(set) var didBootstrap = false
    private(set) var statusDetail: String?

    /// Sections touched by the last update, with how many links each gained.
    private(set) var updateDigest: [String: Int] = [:]
    /// Commits per section over the last month, as a weekly rate.
    private(set) var sectionChurn: [String: Double] = [:]
    /// When each section's cached copy was last fetched from the wiki.
    private var pageFetched: [String: Date] = [:]
    /// Most recently opened sections, newest first.
    private(set) var recentSlugs: [String] = []

    // MARK: - Wiki instance

    static let primaryInstanceKey = "wiki.primaryInstance"
    static let autoFallbackKey = "wiki.autoFallback"
    static let autoRefreshKey = "wiki.autoRefresh"
    static let recentKey = "wiki.recentSections"
    /// Bump when cached pages must be re-parsed (notes keep their links now).
    private static let cacheVersion = 2

    private(set) var preferredInstanceID: String
    private(set) var autoFallback: Bool
    private(set) var needsInstanceSetup: Bool
    private(set) var activeInstance: WikiInstance?
    private(set) var instanceHealth: [String: InstanceHealth] = [:]
    private(set) var lastInstanceProbe: Date?
    private var isProbingInstances = false

    /// A scroll request coming from a cross-reference link (e.g. "Spotify Clients").
    private(set) var pendingJump: WikiJump?

    func requestJump(_ jump: WikiJump) {
        pendingJump = jump
    }

    func clearJump() {
        pendingJump = nil
    }

    var hasUpdateDigest: Bool { !updateDigest.isEmpty }

    func newLinkCount(for slug: String) -> Int { updateDigest[slug] ?? 0 }

    var resumeSlug: String? { recentSlugs.first }

    func recordVisit(slug: String) {
        guard WikiCatalog.bySlug[slug] != nil else { return }
        var updated = recentSlugs.filter { $0 != slug }
        updated.insert(slug, at: 0)
        recentSlugs = Array(updated.prefix(5))
        UserDefaults.standard.set(recentSlugs, forKey: Self.recentKey)
    }

    /// The section URL on the domain the user picked (or a working fallback).
    func wikiURL(slug: String) -> URL? {
        activeInstance?.baseURL.appendingPathComponent(slug)
    }

    var totalEntryCount: Int {
        searchIndex.count
    }

    /// The wiki revision the cached copy came from, e.g. "latest commit bdf3c2a · 16 hours ago".
    var commitLine: String? {
        guard let sha = meta.commitSHA, !sha.isEmpty else { return nil }
        let short = String(sha.prefix(7))
        guard let lastCommitDate else { return "latest commit \(short)" }
        return "latest commit \(short) · \(lastCommitDate.formatted(.relative(presentation: .named)))"
    }

    var statusLine: String {
        switch connection {
        case .offline:
            return lastUpdated == nil ? "Offline · no saved copy" : "Offline · saved copy"
        case .unknown:
            return "Checking for updates…"
        case .online:
            if let lastUpdated {
                return "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
            }
            return "Not updated yet"
        }
    }

    // MARK: - Private state

    private struct Meta: Codable {
        var commitSHA: String?
        var commitDate: Date?
        var lastChecked: Date?
        var lastUpdated: Date?
        var cacheVersion: Int?
        var digest: [String: Int]?
        var digestDate: Date?
        var churn: [String: Double]?
        var churnDate: Date?
        var pageFetched: [String: Date]?
    }

    private var meta = Meta()
    private let session: URLSession
    private let cacheDirectory: URL
    /// How long a local copy is considered fresh before a silent background
    /// check. A busy wiki is checked more often; a quiet one backs off.
    private var refreshInterval: TimeInterval {
        WikiCadence.checkInterval(totalChurnPerWeek: sectionChurn.values.reduce(0, +))
    }

    private static let rawBase = "https://raw.githubusercontent.com/fmhy/edit/main/docs/"
    private static let apiRepo = "https://api.github.com/repos/fmhy/edit"

    init() {
        let defaults = UserDefaults.standard
        let storedInstance = defaults.string(forKey: Self.primaryInstanceKey)
        preferredInstanceID = storedInstance ?? WikiInstances.mainID
        autoFallback = defaults.object(forKey: Self.autoFallbackKey) as? Bool ?? true
        needsInstanceSetup = storedInstance == nil
        recentSlugs = defaults.stringArray(forKey: Self.recentKey) ?? []

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("FMHYWiki", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Lifecycle

    /// Loads the bundled snapshot instantly, then checks GitHub in the background.
    /// First launch stops before caching anything so the domain picker comes first.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        loadMeta()
        loadCachedPages()
        connection = pages.isEmpty ? .unknown : .online
        lastUpdated = meta.lastUpdated
        lastCommitDate = meta.commitDate
        updateDigest = meta.digest ?? [:]
        sectionChurn = meta.churn ?? [:]
        pageFetched = meta.pageFetched ?? [:]

        guard !needsInstanceSetup else { return }

        await probeInstances()
        await loadContent()
    }

    private func loadContent() async {
        // Re-parse the bundled snapshot when the cache format or parser changed.
        if (meta.cacheVersion ?? 1) < Self.cacheVersion {
            pages.removeAll()
            meta.lastChecked = nil
        }
        if pages.count < catalog.count {
            await importBundledSeed()
        }
        meta.cacheVersion = Self.cacheVersion
        rebuildSearchIndex()
        await refreshIfNeeded()
    }

    // MARK: - Wiki domain

    /// Checks every listed instance and resolves which one is actually serving.
    func probeInstances() async {
        guard !isProbingInstances else { return }
        isProbingInstances = true
        defer { isProbingInstances = false }

        for instance in WikiInstances.all {
            instanceHealth[instance.host] = .checking
        }

        await withTaskGroup(of: (String, InstanceHealth).self) { group in
            for instance in WikiInstances.all {
                group.addTask { (instance.host, await Self.probe(instance)) }
            }
            for await (host, health) in group {
                instanceHealth[host] = health
            }
        }

        resolveActiveInstance()
        lastInstanceProbe = .now
    }

    /// Mirrors only matter for opening sections, so a cheap re-check when the app
    /// comes back to the foreground keeps the fallback honest without polling.
    func refreshInstanceHealthIfStale(maxAge: TimeInterval = 30 * 60) async {
        guard !needsInstanceSetup else { return }
        if let lastInstanceProbe, Date().timeIntervalSince(lastInstanceProbe) < maxAge { return }
        await probeInstances()
    }

    private func resolveActiveInstance() {
        let preferred = WikiInstances.instance(for: preferredInstanceID)
        guard autoFallback else {
            activeInstance = preferred
            return
        }

        let ordered = [preferred].compactMap { $0 }
            + WikiInstances.all.filter { $0.host != preferredInstanceID }
        activeInstance = ordered.first { instanceHealth[$0.host] == .online } ?? preferred
    }

    /// Saves the fallback choice made in Settings without going through setup.
    func setAutoFallback(_ enabled: Bool) {
        guard enabled != autoFallback else { return }
        autoFallback = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoFallbackKey)
        resolveActiveInstance()
    }

    /// Saves the domain choice, then starts caching and updating.
    func finishSetup(primary: String, autoFallback: Bool) async {
        UserDefaults.standard.set(primary, forKey: Self.primaryInstanceKey)
        UserDefaults.standard.set(autoFallback, forKey: Self.autoFallbackKey)
        preferredInstanceID = primary
        self.autoFallback = autoFallback
        needsInstanceSetup = false

        await probeInstances()

        if pages.count < catalog.count || searchIndex.isEmpty {
            await loadContent()
        } else {
            await refreshIfNeeded()
        }
    }

    private nonisolated static func probe(_ instance: WikiInstance) async -> InstanceHealth {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)

        var request = URLRequest(url: instance.baseURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("FMHY-wiki-app", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode)
            else { return .offline }
            return .online
        } catch {
            return .offline
        }
    }

    /// Silent update check, respecting the freshness window.
    func refreshIfNeeded() async {
        guard !needsInstanceSetup else { return }
        guard !isRefreshing else { return }
        guard UserDefaults.standard.object(forKey: Self.autoRefreshKey) as? Bool ?? true else { return }
        let lastCheck = meta.lastChecked ?? .distantPast
        if !pages.isEmpty, Date().timeIntervalSince(lastCheck) < refreshInterval {
            return
        }
        await refreshAll(triggered: "auto")
    }

    /// Check GitHub for a newer wiki revision and download only changed pages.
    func refreshAll(triggered: String = "manual") async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let revision = try await latestRevision()
            let cachedPagesMissing = catalog.contains { pages[$0.slug] == nil }
            if revision.sha != meta.commitSHA || cachedPagesMissing {
                let changedSlugs = await changedSlugs(for: revision.sha)
                let slugsToFetch: [String]
                if cachedPagesMissing {
                    slugsToFetch = catalog.map(\.slug).filter { pages[$0] == nil }
                } else if changedSlugs.isEmpty {
                    slugsToFetch = catalog.map(\.slug)
                } else {
                    slugsToFetch = catalog.map(\.slug).filter { changedSlugs.contains($0) }
                }

                var fetchedAny = false
                var digest: [String: Int] = [:]
                for slug in slugsToFetch {
                    let known = Set(pages[slug]?.entryIDs ?? [])
                    if let page = try? await fetchPage(slug: slug) {
                        let added = Set(page.entryIDs).subtracting(known).count
                        if added > 0 { digest[slug] = added }
                        pages[slug] = page
                        save(page)
                        pageFetched[slug] = .now
                        fetchedAny = true
                    }
                }
                // "Updated …" means content actually changed, not that we checked.
                if fetchedAny {
                    meta.lastUpdated = .now
                    meta.digest = digest.isEmpty ? nil : digest
                    meta.digestDate = digest.isEmpty ? nil : .now
                    updateDigest = digest
                }
                meta.commitSHA = revision.sha
                if let date = revision.date {
                    meta.commitDate = date
                }
                statusDetail = slugsToFetch.isEmpty
                    ? "Up to date"
                    : "\(slugsToFetch.count) section\(slugsToFetch.count == 1 ? "" : "s") updated"
            } else {
                statusDetail = "Up to date"
            }

            meta.lastChecked = .now
            lastUpdated = meta.lastUpdated
            lastCommitDate = meta.commitDate
            connection = .online
            rebuildSearchIndex()
            saveMeta()
            await refreshChurnIfStale()
        } catch {
            connection = .offline
            statusDetail = "Using the saved copy"
        }
    }

    /// Pull-to-refresh for a single section. `silent` leaves the loading state
    /// alone, so a stale-but-usable page stays on screen while it is replaced.
    func refreshPage(slug: String, silent: Bool = false) async {
        guard !loadingSlugs.contains(slug) else { return }
        if !silent { loadingSlugs.insert(slug) }
        defer { loadingSlugs.remove(slug) }

        do {
            let page = try await fetchPage(slug: slug)
            pages[slug] = page
            failedSlugs.remove(slug)
            save(page)
            connection = .online
            meta.lastUpdated = .now
            meta.lastChecked = .now
            pageFetched[slug] = .now
            lastUpdated = meta.lastUpdated
            rebuildSearchIndex()
            saveMeta()
        } catch {
            connection = pages[slug] == nil ? .offline : .offline
            failedSlugs.insert(slug)
        }
    }

    /// Re-checks a section on open when its copy is older than its own churn
    /// justifies, so hot sections stay fresh without polling quiet ones.
    func refreshIfStale(slug: String) async {
        guard pages[slug] != nil, connection != .offline else { return }
        guard UserDefaults.standard.object(forKey: Self.autoRefreshKey) as? Bool ?? true else { return }
        let fetched = pageFetched[slug] ?? meta.lastChecked ?? .distantPast
        let interval = WikiCadence.sectionRefreshInterval(
            forChurnPerWeek: sectionChurn[slug] ?? 0
        )
        guard Date().timeIntervalSince(fetched) > interval else { return }
        await refreshPage(slug: slug, silent: true)
    }

    /// Commit counts per section over the last month, cached for a day. GitHub
    /// allows 60 unauthenticated requests an hour and this needs one per section,
    /// so it runs rarely and quietly.
    func refreshChurnIfStale(maxAge: TimeInterval = 24 * 60 * 60) async {
        if let stamp = meta.churnDate, Date().timeIntervalSince(stamp) < maxAge { return }

        let since = ISO8601DateFormatter().string(
            from: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        )
        var measured: [String: Double] = [:]

        for slug in catalog.map(\.slug) {
            guard let count = await commitCount(slug: slug, since: since) else { continue }
            measured[slug] = Double(count) * 7 / 30
        }

        guard !measured.isEmpty else { return }
        sectionChurn = measured
        meta.churnDate = .now
        saveMeta()
    }

    private func commitCount(slug: String, since: String) async -> Int? {
        guard var components = URLComponents(string: "\(Self.apiRepo)/commits") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "path", value: "docs/\(slug).md"),
            URLQueryItem(name: "since", value: since),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        guard let url = components.url,
              let data = try? await fetch(url, accept: "application/vnd.github+json"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return rows.count
    }

    /// e.g. "changes ~3× a week", once the rate is known.
    func churnDescription(for slug: String) -> String? {
        guard let rate = sectionChurn[slug] else { return nil }
        return WikiCadence.description(forChurnPerWeek: rate)
    }

    var tempoLine: String {
        WikiCadence.tempoLine(totalChurnPerWeek: sectionChurn.values.reduce(0, +))
    }

    /// Ensures a section is available, downloading it on first use if needed.
    func loadIfNeeded(slug: String) async {
        if pages[slug] != nil { return }
        await refreshPage(slug: slug)
        if pages[slug] == nil {
            // Last resort: try the bundled snapshot for just this page.
            if let url = Self.seedURL(slug: slug),
               let markdown = try? String(contentsOf: url, encoding: .utf8) {
                let title = WikiCatalog.bySlug[slug]?.title ?? slug
                let page = FMHYMarkdownParser.parse(markdown: markdown, slug: slug, title: title)
                pages[slug] = page
                failedSlugs.remove(slug)
                rebuildSearchIndex()
            }
        }
    }

    // MARK: - Cache

    private func loadMeta() {
        guard let data = try? Data(contentsOf: cacheDirectory.appendingPathComponent("meta.json")),
              let decoded = try? JSONDecoder().decode(Meta.self, from: data)
        else {
            // First launch: remember which wiki revision shipped in the bundle.
            if let seed = Self.seedManifest() {
                meta.commitSHA = seed.commit
                meta.commitDate = seed.commitDateValue
                meta.lastUpdated = seed.generatedDate
                lastCommitDate = meta.commitDate
                saveMeta()
            }
            return
        }
        meta = decoded

        // Older caches stored no commit date: backfill it from the bundled manifest.
        if meta.commitDate == nil,
           let seed = Self.seedManifest(),
           seed.commit == meta.commitSHA,
           let date = seed.commitDateValue {
            meta.commitDate = date
            saveMeta()
        }
    }

    private func saveMeta() {
        meta.churn = sectionChurn.isEmpty ? nil : sectionChurn
        meta.pageFetched = pageFetched.isEmpty ? nil : pageFetched
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: cacheDirectory.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func loadCachedPages() {
        for definition in catalog {
            let url = cacheDirectory.appendingPathComponent("\(definition.slug).json")
            guard let data = try? Data(contentsOf: url),
                  let page = try? JSONDecoder().decode(WikiPage.self, from: data)
            else { continue }
            pages[definition.slug] = page
        }
    }

    private func save(_ page: WikiPage) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(
            to: cacheDirectory.appendingPathComponent("\(page.slug).json"),
            options: .atomic
        )
    }

    private func importBundledSeed() async {
        let definitions = catalog
        let imported: [(String, WikiPage)] = await Task.detached(priority: .userInitiated) {
            definitions.compactMap { definition in
                guard let url = Self.seedURL(slug: definition.slug),
                      let markdown = try? String(contentsOf: url, encoding: .utf8)
                else { return nil }
                return (
                    definition.slug,
                    FMHYMarkdownParser.parse(
                        markdown: markdown,
                        slug: definition.slug,
                        title: definition.title
                    )
                )
            }
        }.value

        for (slug, page) in imported where pages[slug] == nil {
            pages[slug] = page
            save(page)
            // The snapshot is as old as the commit it was built from.
            pageFetched[slug] = meta.commitDate ?? .now
        }
        if !imported.isEmpty, meta.lastUpdated == nil {
            let seed = Self.seedManifest()
            meta.lastUpdated = seed?.generatedDate
            meta.commitSHA = meta.commitSHA ?? seed?.commit
            meta.commitDate = meta.commitDate ?? seed?.commitDateValue
            lastUpdated = meta.lastUpdated
            lastCommitDate = meta.commitDate
            saveMeta()
        }
        if connection == .unknown, !pages.isEmpty {
            connection = .online
        }
    }

    private func rebuildSearchIndex() {
        var items: [SearchItem] = []
        items.reserveCapacity(12_000)
        var live: [String: Set<String>] = [:] as [String: Set<String>]
        for definition in catalog {
            guard let page = pages[definition.slug] else { continue }
            items.append(contentsOf: page.searchItems(pageTitle: definition.title))
            live[definition.slug] = Set(page.entryURLs.map(LinkKey.of))
        }
        searchIndex = items
        liveURLs = live
    }

    /// True only when the bookmark's own section is loaded and no longer lists
    /// the link. A section that has not been downloaded proves nothing either
    /// way, so it never marks anything removed.
    func isGoneFromWiki(urlString: String, slug: String) -> Bool {
        guard let live = liveURLs[slug] else { return false }
        return !live.contains(LinkKey.of(urlString))
    }

    // MARK: - Network

    private func fetchPage(slug: String) async throws -> WikiPage {
        guard let url = URL(string: Self.rawBase + slug + ".md") else {
            throw URLError(.badURL)
        }
        let data = try await fetch(url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let title = WikiCatalog.bySlug[slug]?.title ?? slug
        return await Task.detached(priority: .userInitiated) {
            FMHYMarkdownParser.parse(markdown: markdown, slug: slug, title: title)
        }.value
    }

    private struct Revision {
        let sha: String
        let date: Date?
    }

    /// Latest commit touching `docs`. Reads GitHub's commit feed first so the
    /// unauthenticated REST quota isn't burned on every background check.
    private func latestRevision() async throws -> Revision {
        if let url = URL(string: "https://github.com/fmhy/edit/commits/main.atom"),
           let data = try? await fetch(url, accept: "application/atom+xml"),
           let revision = Self.parseCommitFeed(data) {
            return revision
        }

        guard let url = URL(string: "\(Self.apiRepo)/commits?path=docs&per_page=1") else {
            throw URLError(.badURL)
        }
        struct Commit: Decodable {
            struct Inner: Decodable {
                struct Committer: Decodable { let date: String }
                let committer: Committer
            }
            let sha: String
            let commit: Inner
        }
        let data = try await fetch(url, accept: "application/vnd.github+json")
        let commits = try JSONDecoder().decode([Commit].self, from: data)
        guard let latest = commits.first else { throw URLError(.badServerResponse) }
        return Revision(
            sha: latest.sha,
            date: ISO8601DateFormatter().date(from: latest.commit.committer.date)
        )
    }

    private nonisolated static func parseCommitFeed(_ data: Data) -> Revision? {
        guard let xml = String(data: data, encoding: .utf8),
              let entryStart = xml.range(of: "<entry>"),
              let idStart = xml.range(of: "<id>", range: entryStart.upperBound..<xml.endIndex),
              let idEnd = xml.range(of: "</id>", range: idStart.upperBound..<xml.endIndex)
        else { return nil }

        let id = xml[idStart.upperBound..<idEnd.lowerBound]
        guard let sha = id.split(separator: "/").last.map(String.init), sha.count >= 7 else {
            return nil
        }

        var date: Date?
        if let dateStart = xml.range(of: "<updated>", range: idEnd.upperBound..<xml.endIndex),
           let dateEnd = xml.range(of: "</updated>", range: dateStart.upperBound..<xml.endIndex) {
            date = ISO8601DateFormatter().date(from: String(xml[dateStart.upperBound..<dateEnd.lowerBound]))
        }
        return Revision(sha: sha, date: date)
    }

    /// Markdown files touched by a commit; empty when the commit can't be inspected.
    private func changedSlugs(for sha: String) async -> Set<String> {
        struct Detail: Decodable {
            struct File: Decodable { let filename: String }
            let files: [File]?
        }
        guard let url = URL(string: "\(Self.apiRepo)/commits/\(sha)"),
              let data = try? await fetch(url, accept: "application/vnd.github+json"),
              let detail = try? JSONDecoder().decode(Detail.self, from: data),
              let files = detail.files
        else { return [] }

        var slugs = Set<String>()
        for file in files {
            let name = file.filename
            guard name.hasPrefix("docs/"), name.hasSuffix(".md") else { continue }
            let slug = String(name.dropFirst("docs/".count).dropLast(3))
            if !slug.contains("/") {
                slugs.insert(slug)
            }
        }
        return slugs
    }

    private func fetch(_ url: URL, accept: String = "text/plain") async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("FMHY-wiki-app", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Bundled snapshot

    private struct SeedManifest: Decodable {
        let commit: String?
        let commitDate: String?
        let generated: String?

        var commitDateValue: Date? {
            guard let commitDate else { return nil }
            return ISO8601DateFormatter().date(from: commitDate)
        }

        var generatedDate: Date? {
            guard let generated else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: generated)
        }
    }

    private nonisolated static func seedManifest() -> SeedManifest? {
        guard let url = bundleURL(named: "manifest", extension: "json", subdirectory: "WikiSeed"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(SeedManifest.self, from: data)
    }

    private nonisolated static func seedURL(slug: String) -> URL? {
        bundleURL(named: slug, extension: "md", subdirectory: "WikiSeed")
    }

    private nonisolated static func bundleURL(named name: String, extension ext: String, subdirectory: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/" + subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
