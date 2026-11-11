//
//  TrailTests.swift
//  fmhyTests
//
//  The trail is only useful if it stays a trail: one row per link, newest
//  first, and nothing older than a week. The bookmark audit also leans on
//  LinkKey, so the matching rules are pinned here too.
//

import XCTest
@testable import fmhy

@MainActor
final class TrailTests: XCTestCase {

    private let context = EntryContext(
        pageSlug: "video",
        pageTitle: "Video",
        categoryTitle: "Streaming",
        groupTitle: "Movies"
    )

    private func defaults() -> UserDefaults {
        let suite = "trail-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func entry(_ title: String, _ url: String) -> WikiEntry {
        WikiEntry(title: title, url: URL(string: url)!)
    }

    func testOpeningTheSameLinkAgainMovesItToTheTop() {
        let trail = TrailStore(defaults: defaults())

        trail.record(entry("A", "https://a.example/tool"), context: context)
        trail.record(entry("B", "https://b.example/tool"), context: context)
        trail.record(entry("A renamed", "https://a.example/tool"), context: context)

        XCTAssertEqual(
            trail.entries.map(\.urlString),
            ["https://a.example/tool", "https://b.example/tool"]
        )
        XCTAssertEqual(trail.entries.first?.title, "A renamed")
        XCTAssertEqual(trail.entries.first?.pageSlug, "video")
    }

    func testTheTrailSurvivesBeingReopened() {
        let defaults = defaults()
        TrailStore(defaults: defaults).record(entry("A", "https://a.example"), context: context)

        let reopened = TrailStore(defaults: defaults)
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.entries.first?.title, "A")
    }

    func testClearEmptiesTheTrailForGood() {
        let defaults = defaults()
        let trail = TrailStore(defaults: defaults)
        trail.record(entry("A", "https://a.example"), context: context)

        trail.clear()

        XCTAssertTrue(trail.entries.isEmpty)
        XCTAssertTrue(TrailStore(defaults: defaults).entries.isEmpty)
    }

    func testALinkCountsAsTheSameAcrossCosmeticDifferences() {
        XCTAssertEqual(
            LinkKey.of("https://Example.com/Tool/"),
            LinkKey.of("https://example.com/Tool#install")
        )
        XCTAssertNotEqual(
            LinkKey.of("https://example.com/tool"),
            LinkKey.of("https://example.com/other-tool")
        )
        XCTAssertEqual(
            LinkKey.of("  https://example.com/a?page=2  "),
            LinkKey.of("https://example.com/a?page=2")
        )
    }
}
