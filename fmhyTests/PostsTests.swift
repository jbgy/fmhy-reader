//
//  PostsTests.swift
//  fmhyTests
//
//  The posts screen is only as good as the feed parse, so the RSS reader and the
//  HTML-to-blocks conversion are pinned down here.
//

import XCTest
@testable import fmhy

final class PostsTests: XCTestCase {

    private let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>FMHY blog</title>
            <item>
              <title><![CDATA[Monthly Updates [November]]]></title>
              <link>https://fmhy.net/posts/nov-2026</link>
              <pubDate>Sun, 01 Nov 2026 00:00:00 GMT</pubDate>
              <content:encoded><![CDATA[
                <h2>Wiki Updates</h2>
                <ul><li><p>Added <a href="https://example.com/tool">a tool</a> &amp; friends</p></li></ul>
              ]]></content:encoded>
            </item>
            <item>
              <title><![CDATA[Monthly Updates [October]]]></title>
              <link>https://fmhy.net/posts/oct-2026</link>
              <pubDate>Thu, 01 Oct 2026 00:00:00 GMT</pubDate>
              <content:encoded><![CDATA[<p>October changes.</p>]]></content:encoded>
            </item>
          </channel>
        </rss>
        """

    func testFeedItemsBecomePostsNewestFirst() throws {
        let posts = try FMHYFeed.parse(Data(feed.utf8))

        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts.first?.title, "Monthly Updates [November]")
        XCTAssertEqual(posts.first?.link, "https://fmhy.net/posts/nov-2026")
        XCTAssertEqual(posts.last?.title, "Monthly Updates [October]")
    }

    func testDatesSortPostsByPublishTime() throws {
        let posts = try FMHYFeed.parse(Data(feed.utf8))
        let newest = try XCTUnwrap(posts.first?.published)

        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 1
        let expected = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        XCTAssertEqual(
            Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: newest),
            Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: expected)
        )
    }

    func testHTMLKeepsHeadingsBulletsAndLinks() {
        let html = """
            <h2>Wiki Updates</h2>
            <ul><li><p>Added <a href="https://example.com/tool">a tool</a> &amp; friends</p></li></ul>
            <p>That&#39;s all.</p>
            """

        let blocks = FMHYFeed.blocks(from: html)

        XCTAssertEqual(blocks.map(\.kind), [.heading, .bullet, .paragraph])
        XCTAssertEqual(blocks[0].text, "Wiki Updates")
        XCTAssertEqual(blocks[1].text, "Added [a tool](https://example.com/tool) & friends")
        XCTAssertEqual(blocks[2].text, "That's all.")
    }

    func testPreambleBeforeTheFirstHeadingIsDropped() {
        let html = """
            <h1>Monthly Updates [November]</h1>
            <p>November 2026 updates • Nov 1</p>
            <p>[nbats](https://github.com/nbats)</p>
            <h2>Wiki Updates</h2>
            <ul><li><p>Added a thing</p></li></ul>
            """

        let blocks = FMHYFeed.newsBlocks(from: html, title: "Monthly Updates [November]")

        XCTAssertEqual(blocks.map(\.kind), [.heading, .bullet])
        XCTAssertEqual(blocks.first?.text, "Wiki Updates")
    }

    func testAnchorPermalinksAreDropped() {
        let html = ##"<h1 id="wiki-updates">Wiki Updates <a class="header-anchor" href="#wiki-updates" aria-label="Permalink">​</a></h1>"##
        XCTAssertEqual(FMHYFeed.blocks(from: html).map(\.text), ["Wiki Updates"])
    }

    func testExcerptStripsMarkdown() {
        let post = FMHYPost(
            title: "Monthly Updates [November]",
            link: "https://fmhy.net/posts/nov-2026",
            published: .now,
            blocks: [PostBlock(kind: .paragraph, text: "Read [the notes](https://example.com) now.")]
        )
        XCTAssertEqual(post.excerpt, "Read the notes now.")
    }

    func testGarbageIsRejected() {
        XCTAssertThrowsError(try FMHYFeed.parse(Data("not xml".utf8)))
    }
}
