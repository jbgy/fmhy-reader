//
//  RoutingTests.swift
//  fmhyTests
//
//  Cross-references are the difference between staying in the app and being
//  dumped into a browser, so both link styles have to keep routing.
//

import XCTest
@testable import fmhy

final class RoutingTests: XCTestCase {

    private func target(_ url: String) -> WikiLinkRouter.Target? {
        guard let url = URL(string: url) else {
            XCTFail("bad fixture url: \(url)")
            return nil
        }
        return WikiLinkRouter.target(for: url)
    }

    func testWikiSectionRoutesToItsSlug() {
        XCTAssertEqual(target("https://fmhy.net/audio")?.slug, "audio")
        XCTAssertEqual(target("https://fmhy.net/internet-tools")?.slug, "internet-tools")
    }

    func testWikiAnchorBecomesAGroupHint() {
        XCTAssertEqual(target("https://fmhy.net/audio#spotify-tools")?.group, "spotify tools")
    }

    func testLegacyRedditSlugsMapToCurrentSections() {
        XCTAssertEqual(
            target("https://www.reddit.com/r/Freemediaheckyeah/wiki/dev-tools")?.slug,
            "developer-tools"
        )
        XCTAssertEqual(
            target("https://www.reddit.com/r/Freemediaheckyeah/wiki/torrent")?.slug,
            "torrenting"
        )
    }

    func testRedditEscapedAnchorsAreDecoded() {
        let jump = target("https://www.reddit.com/r/fmhy/wiki/internet-tools#wiki_.25BA_search_engines")
        XCTAssertEqual(jump?.slug, "internet-tools")
        XCTAssertEqual(jump?.group, "► search engines")
    }

    func testRedditHTMLEntitiesInAnchorsAreDecoded() {
        let jump = target("https://www.reddit.com/r/fmhy/wiki/mobile#app_patchers_.26amp.3B_modifiers")
        XCTAssertEqual(jump?.group, "app patchers & modifiers")
    }

    func testNonWikiAndUnknownLinksDoNotRoute() {
        XCTAssertNil(target("https://example.com/audio"))
        XCTAssertNil(target("https://fmhy.net/index"))
        XCTAssertNil(target("https://www.reddit.com/r/fmhy/comments/abc/hello"))
    }
}
