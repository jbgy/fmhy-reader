//
//  SearchRankingTests.swift
//  fmhyTests
//

import XCTest
@testable import fmhy

final class SearchRankingTests: XCTestCase {

    private func item(
        title: String,
        summary: String = "",
        group: String = "",
        category: String = "Tools",
        url: String = "https://example.com",
        extras: [String] = []
    ) -> SearchItem {
        let entry = WikiEntry(
            title: title,
            url: URL(string: url)!,
            summary: summary,
            extraLinks: extras.compactMap { WikiLink(title: $0, url: URL(string: "https://link.example")!) }
        )
        return SearchItem(
            id: title,
            entry: entry,
            pageSlug: "tools",
            pageTitle: "Tools",
            categoryTitle: category,
            groupTitle: group
        )
    }

    private func titles(_ query: String, _ items: [SearchItem]) -> [String] {
        WikiSearch.rank(items, query: query).map(\.entry.title)
    }

    func testExactTitleBeatsSummaryMention() {
        let items = [
            item(title: "Music Player", summary: "Integrates with Spotify"),
            item(title: "Spotify"),
        ]
        XCTAssertEqual(titles("spotify", items).first, "Spotify")
    }

    func testTitlePrefixBeatsSubstring() {
        let items = [item(title: "SuperPlayer"), item(title: "Player")]
        XCTAssertEqual(titles("player", items), ["Player", "SuperPlayer"])
    }

    func testGroupNameMatches() {
        let items = [item(title: "Spicetify", group: "Spotify Tools"), item(title: "VLC")]
        XCTAssertEqual(titles("spotify", items), ["Spicetify"])
    }

    func testHostMatches() {
        let items = [item(title: "Some Repo", url: "https://github.com/owner/repo")]
        XCTAssertEqual(titles("github.com", items), ["Some Repo"])
    }

    func testEveryWordMustMatch() {
        let items = [item(title: "Chrome", summary: "Fast browser")]
        XCTAssertTrue(WikiSearch.rank(items, query: "chrome password").isEmpty)
        XCTAssertEqual(titles("chrome browser", items), ["Chrome"])
    }

    func testMatchingIgnoresCaseAndDiacritics() {
        let items = [item(title: "Pokémon Showdown")]
        XCTAssertEqual(titles("POKEMON", items), ["Pokémon Showdown"])
        XCTAssertEqual(titles("pokémon", items), ["Pokémon Showdown"])
    }

    func testLimitCapsTheResultCount() {
        let items = (0..<300).map { item(title: "Site \($0)") }
        XCTAssertEqual(WikiSearch.rank(items, query: "site", limit: 5).count, 5)
        XCTAssertEqual(WikiSearch.rank(items, query: "site").count, WikiSearch.defaultLimit)
    }

    func testBlankQueryReturnsNothing() {
        let items = [item(title: "Spotify")]
        XCTAssertTrue(WikiSearch.rank(items, query: "   ").isEmpty)
    }

    func testTiesPreferTheShorterTitle() {
        let items = [item(title: "Long Name Player"), item(title: "Player")]
        XCTAssertEqual(titles("player", items).first, "Player")
    }
}
