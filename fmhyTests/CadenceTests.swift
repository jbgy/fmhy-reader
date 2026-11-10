//
//  CadenceTests.swift
//  fmhyTests
//
//  Refresh timing is the only thing standing between a hot section and a
//  week-old copy, so the thresholds are pinned here rather than tuned by feel.
//

import XCTest
@testable import fmhy

final class CadenceTests: XCTestCase {

    func testHotSectionsAreRecheckedWithinTheHour() {
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 20), 3600)
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 4), 3600)
        // Just below the threshold: every six hours is enough.
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 3.9), 21_600)
    }

    func testQuietSectionsBackOff() {
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 1), 21_600)
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 0.5), 86_400)
        XCTAssertEqual(WikiCadence.sectionRefreshInterval(forChurnPerWeek: 0), 259_200)
    }

    func testWholeRepositoryIntervalFollowsTotalChurn() {
        XCTAssertEqual(WikiCadence.checkInterval(totalChurnPerWeek: 25), 7200)
        XCTAssertEqual(WikiCadence.checkInterval(totalChurnPerWeek: 10), 7200)
        XCTAssertEqual(WikiCadence.checkInterval(totalChurnPerWeek: 4), 14_400)
        XCTAssertEqual(WikiCadence.checkInterval(totalChurnPerWeek: 0), 21_600)
    }

    func testDescriptionsStayReadable() {
        XCTAssertEqual(WikiCadence.description(forChurnPerWeek: 9), "changes daily")
        XCTAssertEqual(WikiCadence.description(forChurnPerWeek: 3.4), "changes ~3× a week")
        XCTAssertEqual(WikiCadence.description(forChurnPerWeek: 1.2), "changes about weekly")
        XCTAssertEqual(WikiCadence.description(forChurnPerWeek: 0.5), "changes about monthly")
        XCTAssertEqual(WikiCadence.description(forChurnPerWeek: 0), "rarely changes")
    }

    func testTempoLineDescribesTheWholeWiki() {
        XCTAssertTrue(WikiCadence.tempoLine(totalChurnPerWeek: 12).hasPrefix("busy"))
        XCTAssertTrue(WikiCadence.tempoLine(totalChurnPerWeek: 5).hasPrefix("steady"))
        XCTAssertTrue(WikiCadence.tempoLine(totalChurnPerWeek: 1).hasPrefix("quiet"))
        XCTAssertEqual(
            WikiCadence.tempoLine(totalChurnPerWeek: 0),
            "no changes in the last month"
        )
    }
}
