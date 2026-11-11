//
//  Trail.swift
//  fmhy
//
//  The links opened over the past week, kept so a tool found while browsing can
//  be found again without having been bookmarked.
//

import Foundation
import Observation

struct TrailEntry: Identifiable, Codable, Hashable, Sendable {
    let urlString: String
    let title: String
    let pageSlug: String
    let pageTitle: String
    let summary: String
    let openedAt: Date

    var id: String { urlString }
    var url: URL? { URL(string: urlString) }
}

@MainActor
@Observable
final class TrailStore {
    static let shared = TrailStore()

    private(set) var entries: [TrailEntry] = []

    private static let storageKey = "trailEntries"
    private static let limit = 60
    private static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Newest first, one row per link: opening the same link again only brings
    /// it back to the top instead of listing it twice.
    func record(_ entry: WikiEntry, context: EntryContext) {
        let item = TrailEntry(
            urlString: entry.url.absoluteString,
            title: entry.title,
            pageSlug: context.pageSlug,
            pageTitle: context.pageTitle,
            summary: entry.summary,
            openedAt: .now
        )

        entries.removeAll { $0.urlString == item.urlString }
        entries.insert(item, at: 0)
        entries = Array(entries.prefix(Self.limit))
        prune()
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// A week is long enough to come back to something, short enough that the
    /// list stays a trail rather than a history.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.lifetime)
        entries.removeAll { $0.openedAt < cutoff }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([TrailEntry].self, from: data)
        else { return }
        entries = stored
        prune()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
