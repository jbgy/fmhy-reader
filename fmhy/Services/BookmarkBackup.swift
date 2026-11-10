//
//  BookmarkBackup.swift
//  fmhy
//
//  Opt-in safety copy of the bookmarks that lives outside the SwiftData store.
//  Nothing is written until the user turns it on, and nothing is merged back
//  into the store without confirmation.
//

import Foundation
import SwiftData

/// The JSON copy that outlives a broken store or an app reinstall.
struct BookmarkBackupStore {
    static let filename = "fmhy-bookmarks-backup.json"

    let directory: URL

    var fileURL: URL { directory.appendingPathComponent(Self.filename) }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    var modifiedAt: Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }

    func records() -> [BookmarkRecord]? {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? BookmarkArchive.decode(data),
              !records.isEmpty
        else { return nil }
        return records
    }

    func save(_ records: [BookmarkRecord]) throws {
        guard !records.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try BookmarkArchive.encode(records).write(to: fileURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum BookmarkBackup {
    /// Off until the user turns it on: no copy is written before that.
    static let enabledKey = "bookmarks.backupEnabled"
    /// Modification date of the copy the user already said "not now" to.
    static let declinedBackupKey = "bookmarks.backupDeclinedFor"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var store: BookmarkBackupStore {
        BookmarkBackupStore(directory: directory)
    }

    private static var directory: URL {
        let manager = FileManager.default
        #if os(iOS)
        // Documents shows up in the Files app, so the copy can be taken out
        // before the app is deleted.
        return manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FMHY", isDirectory: true)
        #endif
    }

    static func snapshot(in context: ModelContext) {
        guard isEnabled else { return }
        let bookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        snapshot(bookmarks)
    }

    static func snapshot(_ bookmarks: [Bookmark]) {
        guard isEnabled, !bookmarks.isEmpty else { return }
        try? store.save(bookmarks.map { BookmarkRecord(bookmark: $0) })
    }

    /// A copy worth offering, only when the store has nothing in it.
    static func restoreCandidate(bookmarkCount: Int) -> [BookmarkRecord]? {
        guard bookmarkCount == 0, let modified = store.modifiedAt else { return nil }
        let declined = UserDefaults.standard.object(forKey: declinedBackupKey) as? Date
        guard declined != modified else { return nil }
        return store.records()
    }

    static func acceptRestore() {
        UserDefaults.standard.removeObject(forKey: declinedBackupKey)
    }

    /// "Not now" keeps the file and stops asking about this same copy.
    static func declineRestore() {
        guard let modified = store.modifiedAt else { return }
        UserDefaults.standard.set(modified, forKey: declinedBackupKey)
    }
}

extension BookmarkRecord {
    init(bookmark: Bookmark) {
        self.init(
            url: bookmark.urlString,
            title: bookmark.title,
            summary: bookmark.summary,
            pageSlug: bookmark.pageSlug,
            pageTitle: bookmark.pageTitle,
            categoryTitle: bookmark.categoryTitle,
            groupTitle: bookmark.groupTitle,
            folder: bookmark.folder,
            createdAt: bookmark.createdAt
        )
    }
}

/// Merge shared by the import sheet and the backup restore: links already
/// saved keep their place, an imported folder is still adopted.
@MainActor
enum BookmarkImport {
    @discardableResult
    static func merge(_ records: [BookmarkRecord], into context: ModelContext) -> (added: Int, updated: Int) {
        let existing = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        var byURL = Dictionary(
            existing.map { ($0.urlString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var added = 0
        var updated = 0

        for record in records {
            if let bookmark = byURL[record.url] {
                if let folder = record.folder, !folder.isEmpty, bookmark.folder != folder {
                    bookmark.folder = folder
                    updated += 1
                }
                continue
            }

            let bookmark = Bookmark(
                urlString: record.url,
                title: record.title,
                summary: record.summary,
                pageSlug: record.pageSlug,
                pageTitle: record.pageTitle,
                categoryTitle: record.categoryTitle,
                groupTitle: record.groupTitle,
                folder: record.folder,
                createdAt: record.createdAt ?? .now
            )
            context.insert(bookmark)
            byURL[record.url] = bookmark
            added += 1
        }

        try? context.save()
        BookmarkBackup.snapshot(in: context)
        return (added, updated)
    }
}
