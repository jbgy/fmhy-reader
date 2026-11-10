//
//  Bookmark.swift
//  fmhy
//
//  Locally saved entry, persisted with SwiftData.
//

import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var urlString: String
    var title: String
    var summary: String
    var pageSlug: String
    var pageTitle: String
    var categoryTitle: String
    var groupTitle: String
    /// nil means unfiled; folders are free-form names the user types.
    var folder: String?
    var createdAt: Date

    init(
        urlString: String,
        title: String,
        summary: String,
        pageSlug: String,
        pageTitle: String,
        categoryTitle: String,
        groupTitle: String,
        folder: String? = nil,
        createdAt: Date = .now
    ) {
        self.urlString = urlString
        self.title = title
        self.summary = summary
        self.pageSlug = pageSlug
        self.pageTitle = pageTitle
        self.categoryTitle = categoryTitle
        self.groupTitle = groupTitle
        self.folder = folder
        self.createdAt = createdAt
    }

    convenience init(entry: WikiEntry, context: EntryContext) {
        self.init(
            urlString: entry.url.absoluteString,
            title: entry.title,
            summary: entry.summary,
            pageSlug: context.pageSlug,
            pageTitle: context.pageTitle,
            categoryTitle: context.categoryTitle,
            groupTitle: context.groupTitle
        )
    }

    var url: URL? { URL(string: urlString) }
}
