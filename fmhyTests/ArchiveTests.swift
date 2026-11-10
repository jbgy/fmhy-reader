//
//  ArchiveTests.swift
//  fmhyTests
//
//  Bookmarks only survive a reinstall if the exported JSON can be read back
//  exactly, so the round trip is worth pinning down.
//

import XCTest
@testable import fmhy

final class ArchiveTests: XCTestCase {

    private let saved = Date(timeIntervalSince1970: 1_700_000_000)

    private var records: [BookmarkRecord] {
        [
            BookmarkRecord(
                url: "https://firefox.com",
                title: "Firefox",
                summary: "Open source browser",
                pageSlug: "internet-tools",
                pageTitle: "Internet Tools",
                categoryTitle: "Browsers",
                groupTitle: "Browsers",
                folder: "Browsers",
                createdAt: saved
            ),
            BookmarkRecord(
                url: "https://duckduckgo.com",
                title: "DuckDuckGo",
                pageSlug: "internet-tools",
                pageTitle: "Internet Tools",
                categoryTitle: "Search",
                groupTitle: "Search Engines",
                folder: nil,
                createdAt: saved
            ),
        ]
    }

    func testRoundTripKeepsEveryField() throws {
        let data = BookmarkArchive.encode(records, exportedAt: saved)
        let decoded = try BookmarkArchive.decode(data)
        XCTAssertEqual(decoded, records)
    }

    func testExportIsReadableJSONWithAVersion() throws {
        let data = BookmarkArchive.encode(records, exportedAt: saved)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, BookmarkArchive.version)
        XCTAssertNotNil(object["exportedAt"] as? String)
        XCTAssertEqual((object["bookmarks"] as? [[String: Any]])?.count, 2)
    }

    func testDecodingGarbageThrows() {
        XCTAssertThrowsError(try BookmarkArchive.decode(Data("not json".utf8)))
    }

    func testSuggestedFilenameIsDatedJSON() {
        let name = BookmarkArchive.suggestedFilename(now: saved)
        XCTAssertNotNil(
            name.range(of: #"^fmhy-bookmarks-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression),
            name
        )
    }
}
