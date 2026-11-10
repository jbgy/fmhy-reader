//
//  ParserTests.swift
//  fmhyTests
//
//  The parser is the piece most likely to break when FMHY changes its format,
//  so these fixtures pin down the shapes it has to keep understanding.
//

import XCTest
@testable import fmhy

final class ParserTests: XCTestCase {

    private let sample = """
    # ► Internet Tools

    Everything for browsing, extensions and search.

    ## ▷ Browsers

    * ⭐ [Firefox](https://www.mozilla.org/firefox/) - Open source browser / Windows / macOS / Linux
    * [Chrome](https://www.google.com/chrome/) - Google's browser
      Continued description of Chrome.
    * [Brave](https://brave.com) - [GitHub](https://github.com/brave/brave-browser)

    !!!note Check [FMHY privacy](https://fmhy.net/privacy) for trackers.

    ## ► Search Engines

    * [DuckDuckGo](https://duckduckgo.com) - Private search
    * [Startpage](https://www.startpage.com) - [2](https://mirror.example)
    """

    private func parse(_ markdown: String? = nil) -> WikiPage {
        FMHYMarkdownParser.parse(
            markdown: markdown ?? sample,
            slug: "internet-tools",
            title: "Internet Tools"
        )
    }

    func testCategoriesGroupsAndEntryOrder() throws {
        let page = parse()
        XCTAssertEqual(page.categories.count, 1)

        let category = try XCTUnwrap(page.categories.first)
        XCTAssertEqual(category.title, "Internet Tools")
        XCTAssertEqual(category.groups.map(\.title), ["Browsers", "Search Engines"])
        XCTAssertEqual(category.groups.map(\.level), [2, 2])
        XCTAssertEqual(category.entryCount, 5)
        XCTAssertNil(category.remote)
    }

    func testIntroParagraphAndCalloutBecomeCategoryNotes() throws {
        let category = try XCTUnwrap(parse().categories.first)
        XCTAssertTrue(category.notes.contains { $0.hasPrefix("Everything for browsing") })
        XCTAssertTrue(category.notes.contains { $0.contains("FMHY privacy") })
        // The callout belongs to the section, not to the last group.
        XCTAssertFalse(category.groups[0].notes.contains { $0.contains("FMHY privacy") })
    }

    func testStarredEntryKeepsItsKindAndSummary() throws {
        let entry = try XCTUnwrap(parse().categories.first?.groups[0].entries.first)
        XCTAssertEqual(entry.title, "Firefox")
        XCTAssertEqual(entry.kind, .starred)
        XCTAssertEqual(entry.summary, "Open source browser / Windows / macOS / Linux")
        XCTAssertTrue(entry.extraLinks.isEmpty)
        XCTAssertEqual(entry.url.absoluteString, "https://www.mozilla.org/firefox/")
    }

    func testWrappedContinuationIsAppendedToThePreviousEntry() throws {
        let entries = try XCTUnwrap(parse().categories.first?.groups[0].entries)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].title, "Chrome")
        XCTAssertEqual(entries[1].summary, "Google's browser Continued description of Chrome.")
    }

    func testSecondaryLinksBecomeExtras() throws {
        let entries = try XCTUnwrap(parse().categories.first?.groups[0].entries)
        let brave = try XCTUnwrap(entries.last)
        XCTAssertEqual(brave.title, "Brave")
        XCTAssertEqual(brave.extraLinks.map(\.title), ["GitHub"])
        XCTAssertEqual(brave.summary, "")
    }

    func testMirrorLinksAreNotKeptAsExtras() throws {
        let groups = try XCTUnwrap(parse().categories.first?.groups)
        let startpage = try XCTUnwrap(groups[1].entries.last)
        XCTAssertEqual(startpage.title, "Startpage")
        XCTAssertTrue(startpage.extraLinks.isEmpty)
    }

    func testTablesAndSeparatorsAreIgnored() {
        let page = parse("""
        # ► Tools

        | Name | Link |
        |------|------|
        ***
        * [Only Entry](https://only.example) - The one that counts
        """)
        XCTAssertEqual(page.entryCount, 1)
        XCTAssertEqual(page.categories.first?.groups.first?.entries.first?.title, "Only Entry")
    }

    func testHeadingLinkBecomesTheCategoryRemote() throws {
        let page = parse("""
        # [► Tools](https://fmhy.net/tools)

        * [A](https://a.example) - First
        """)
        let category = try XCTUnwrap(page.categories.first)
        XCTAssertEqual(category.title, "Tools")
        XCTAssertEqual(category.remote?.url.absoluteString, "https://fmhy.net/tools")
    }

    func testBoldLabelBecomesTheSummary() throws {
        let page = parse("""
        # ► Tools

        ## ▷ Download Managers

        * **Download Managers: [AB Download Manager](https://abdm.example)**
        """)
        let entry = try XCTUnwrap(page.categories.first?.groups.first?.entries.first)
        XCTAssertEqual(entry.title, "AB Download Manager")
        XCTAssertEqual(entry.summary, "Download Managers")
    }

    func testAnchorsResolveToGroups() throws {
        let page = parse()
        let groups = try XCTUnwrap(page.categories.first?.groups)
        XCTAssertEqual(page.groupID(matching: "Browsers"), groups[0].id)
        XCTAssertEqual(page.groupID(matching: "search engines"), groups[1].id)
        XCTAssertEqual(page.groupID(matching: "► Browsers"), groups[0].id)
        XCTAssertNil(page.groupID(matching: "torrent clients"))
        // Generic heading words alone must not match anything.
        XCTAssertNil(page.groupID(matching: "misc tools"))
    }

    func testSearchItemsCoverEveryEntryOnce() throws {
        let page = parse()
        let items = page.searchItems(pageTitle: page.title)
        XCTAssertEqual(items.count, page.entryCount)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertEqual(items.first?.pageSlug, "internet-tools")
        XCTAssertEqual(items.first?.pageTitle, "Internet Tools")
    }
}
