//
//  BackupTests.swift
//  fmhyTests
//
//  The opt-in backup only helps if a copy written before a crash can be read
//  back exactly, so the file store is pinned down here.
//

import XCTest
@testable import fmhy

final class BackupTests: XCTestCase {

    private var directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("fmhy-backup-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    private var store: BookmarkBackupStore { BookmarkBackupStore(directory: directory) }

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
        ]
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSnapshotRoundTripsThroughDisk() throws {
        XCTAssertFalse(store.exists)

        try store.save(records)

        XCTAssertTrue(store.exists)
        XCTAssertEqual(store.records(), records)
        XCTAssertNotNil(store.modifiedAt)
    }

    func testEmptySnapshotWritesNothing() throws {
        try store.save([])
        XCTAssertFalse(store.exists)
    }

    func testUnreadableFileIsNotOffered() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertTrue(store.exists)
        XCTAssertNil(store.records())

        store.remove()
        XCTAssertFalse(store.exists)
    }
}
