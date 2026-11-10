//
//  BookmarkArchive.swift
//  fmhy
//
//  Portable JSON for bookmarks, so folders survive reinstalls and sideloads.
//

import Foundation

struct BookmarkRecord: Codable, Equatable, Sendable {
    var url: String
    var title: String
    var summary: String = ""
    var pageSlug: String = ""
    var pageTitle: String = ""
    var categoryTitle: String = ""
    var groupTitle: String = ""
    var folder: String?
    var createdAt: Date?
}

enum BookmarkArchive {
    static let version = 1

    struct Payload: Codable {
        var version: Int
        var exportedAt: Date
        var bookmarks: [BookmarkRecord]
    }

    static func encode(_ records: [BookmarkRecord], exportedAt: Date = .now) -> Data {
        let payload = Payload(version: version, exportedAt: exportedAt, bookmarks: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(payload)) ?? Data()
    }

    static func decode(_ data: Data) throws -> [BookmarkRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data).bookmarks
    }

    static func suggestedFilename(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "fmhy-bookmarks-\(formatter.string(from: now)).json"
    }
}
