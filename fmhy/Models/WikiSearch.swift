//
//  WikiSearch.swift
//  fmhy
//
//  Ranks the in-memory index so the closest match wins instead of whichever
//  entry happened to be parsed first.
//

import Foundation

enum WikiSearch {

    static let defaultLimit = 250

    /// Every entry that contains all the words in the query, best match first.
    static func rank(
        _ items: [SearchItem],
        query: String,
        limit: Int = defaultLimit
    ) -> [SearchItem] {
        let prepared = Prepared(query)
        guard prepared.isUsable else { return [] }

        var scored: [(item: SearchItem, score: Int)] = []
        for item in items {
            if let score = prepared.score(for: item) {
                scored.append((item, score))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let left = lhs.item.entry.title
            let right = rhs.item.entry.title
            if left.count != right.count { return left.count < right.count }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        return scored.prefix(limit).map(\.item)
    }

    private struct Prepared {
        let phrase: String
        let tokens: [String]

        init(_ query: String) {
            phrase = Self.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
            tokens = phrase
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        }

        var isUsable: Bool { !phrase.isEmpty && !tokens.isEmpty }

        func score(for item: SearchItem) -> Int? {
            let title = Self.fold(item.entry.title)
            let group = Self.fold(item.groupTitle)
            let category = Self.fold(item.categoryTitle)
            let summary = Self.fold(item.entry.summary)
            let url = Self.fold(item.entry.url.absoluteString)
            let host = Self.fold(item.entry.url.host ?? "")
            let extras = item.entry.extraLinks.map { Self.fold($0.title) }

            // Every word has to appear somewhere, so "chrome password" does not
            // return every browser in the wiki.
            let fields = [title, group, summary, category, host, url] + extras
            for token in tokens where !fields.contains(where: { $0.contains(token) }) {
                return nil
            }

            var score = 0

            // Where the phrase lands matters more than how often it lands.
            if title == phrase {
                score += 1000
            } else if title.hasPrefix(phrase) {
                score += 650
            } else if title.split(separator: " ").contains(where: { $0.hasPrefix(phrase) }) {
                score += 500
            } else if title.contains(phrase) {
                score += 380
            }

            if summary.contains(phrase) { score += 90 }
            if group.contains(phrase) { score += 120 }
            if category.contains(phrase) { score += 40 }
            if host.contains(phrase) {
                score += 70
            } else if url.contains(phrase) {
                score += 30
            }
            if extras.contains(where: { $0.contains(phrase) }) { score += 25 }

            // Multi-word queries: reward titles that carry more of the words.
            if tokens.count > 1 {
                score += tokens.filter { title.contains($0) }.count * 60
            }

            return score
        }

        /// Case and diacritics should not matter: "pokemon" finds "Pokémon".
        static func fold(_ text: String) -> String {
            text.folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: nil
            )
        }
    }
}
