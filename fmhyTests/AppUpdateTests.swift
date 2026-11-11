//
//  AppUpdateTests.swift
//  fmhyTests
//
//  The update row is the only thing telling a sideloaded copy that a new build
//  exists, so the comparison against the feed is pinned here.
//

import XCTest
@testable import fmhy

final class AppUpdateTests: XCTestCase {

    private func feed(_ apps: [[String: String]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["apps": apps])
    }

    func testVersionsCompareNumberByNumber() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("2.0.1")), try XCTUnwrap(AppVersion("2.0")))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("2.10")), try XCTUnwrap(AppVersion("2.9")))
        XCTAssertEqual(try XCTUnwrap(AppVersion("2.0.0")), try XCTUnwrap(AppVersion("2")))
        XCTAssertNil(AppVersion("2.0 beta"))
    }

    func testPatchReleaseIsNewerThanTheRunningCopy() throws {
        let data = try feed([
            [
                "version": "2.0.1",
                "buildVersion": "10",
                "localizedDescription": "Import picker",
                "downloadURL": "https://example.com/FMHY.ipa",
            ],
        ])
        let latest = try XCTUnwrap(AppReleaseFeed.latest(in: data))

        XCTAssertEqual(latest.versionLine, "2.0.1 (10)")
        XCTAssertTrue(AppReleaseFeed.isNewer(latest, thanVersion: "2.0", build: "9"))
    }

    func testPublishedBuildIsNotOfferedAgain() throws {
        let data = try feed([["version": "2.0", "buildVersion": "9"]])
        let latest = try XCTUnwrap(AppReleaseFeed.latest(in: data))

        XCTAssertFalse(AppReleaseFeed.isNewer(latest, thanVersion: "2.0", build: "9"))
        XCTAssertFalse(AppReleaseFeed.isNewer(latest, thanVersion: "2.0.1", build: "10"))
    }

    func testNewestRowWinsWhateverTheFeedOrder() throws {
        let data = try feed([
            ["version": "2.0", "buildVersion": "9"],
            ["version": "2.0.1", "buildVersion": "10"],
            ["version": "1.7", "buildVersion": "8"],
        ])
        let latest = try XCTUnwrap(AppReleaseFeed.latest(in: data))

        XCTAssertEqual(latest.versionLine, "2.0.1 (10)")
    }

    func testRepublishedVersionUsesTheBuildNumber() throws {
        let data = try feed([["version": "2.0.1", "buildVersion": "11"]])
        let latest = try XCTUnwrap(AppReleaseFeed.latest(in: data))

        XCTAssertTrue(AppReleaseFeed.isNewer(latest, thanVersion: "2.0.1", build: "10"))
    }
}
