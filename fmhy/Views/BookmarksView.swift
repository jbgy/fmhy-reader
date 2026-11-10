//
//  BookmarksView.swift
//  fmhy
//
//  Saved links, grouped into folders, with JSON export/import.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct BookmarkSection: Identifiable {
    let title: String
    let items: [Bookmark]
    var id: String { title }
}

struct BookmarksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWikiURL) private var openURL
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]

    @State private var query = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isNamingFolder = false
    @State private var newFolderName = ""
    @State private var folderTarget: Bookmark?
    @State private var exportDocument: BookmarkExportDocument?
    @State private var statusMessage: String?

    private var folders: [String] {
        Set(bookmarks.compactMap { $0.folder }.filter { !$0.isEmpty }).sorted()
    }

    private var filtered: [Bookmark] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(text)
                || $0.summary.localizedCaseInsensitiveContains(text)
                || $0.pageTitle.localizedCaseInsensitiveContains(text)
                || $0.groupTitle.localizedCaseInsensitiveContains(text)
                || ($0.folder ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    private var sections: [BookmarkSection] {
        var buckets: [String: [Bookmark]] = [:]
        for bookmark in filtered {
            buckets[bookmark.folder ?? "", default: []].append(bookmark)
        }

        var result: [BookmarkSection] = []
        if let unfiled = buckets.removeValue(forKey: ""), !unfiled.isEmpty {
            result.append(BookmarkSection(title: "Unfiled", items: unfiled))
        }
        for name in buckets.keys.sorted() {
            result.append(BookmarkSection(title: name, items: buckets[name] ?? []))
        }
        return result
    }

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks Yet", systemImage: "star")
                } description: {
                    Text("Tap the star next to any link to keep it here, available offline.")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { bookmark in
                                row(bookmark)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            remove(bookmark)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }

                    Section {} footer: {
                        Text(statusMessage ?? "\(bookmarks.count) saved · stored only on this device")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .inlineSearchable(text: $query, prompt: "Search bookmarks")
            }
        }
        .navigationTitle("Bookmarks")
        .toolbar { toolbarContent }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { folderTarget = nil }
            Button("Create") { createFolder() }
        } message: {
            Text("The bookmark moves into that folder.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BookmarkArchive.suggestedFilename()
        ) { result in
            switch result {
            case .success:
                statusMessage = "Exported \(bookmarks.count) bookmark\(bookmarks.count == 1 ? "" : "s")."
            case .failure(let error):
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            exportImportMenu
        }
        #else
        ToolbarItem(placement: .automatic) {
            exportImportMenu
        }
        #endif
    }

    private var exportImportMenu: some View {
        Menu {
            Button("Export Bookmarks…", systemImage: "square.and.arrow.up") {
                startExport()
            }
            Button("Import Bookmarks…", systemImage: "square.and.arrow.down") {
                statusMessage = nil
                isImporting = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("Bookmark folders, export and import")
    }

    // MARK: - Rows

    private func row(_ bookmark: Bookmark) -> some View {
        Button {
            if let url = bookmark.url { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .frame(width: 16, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(contextLine(bookmark))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if !bookmark.summary.isEmpty {
                        Text(bookmark.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url = bookmark.url {
                Button("Open", systemImage: "safari") { openURL(url) }
                Button("Open in Default Browser", systemImage: "arrow.up.forward.app") {
                    ExternalBrowser.open(url)
                }
                Button("Copy Link", systemImage: "doc.on.doc") {
                    Clipboard.copy(url.absoluteString)
                }
                Divider()
            }

            Menu("Move to Folder", systemImage: "folder") {
                Button("Unfiled") { assign(bookmark, folder: nil) }
                if !folders.isEmpty {
                    Divider()
                    ForEach(folders, id: \.self) { name in
                        Button(name) { assign(bookmark, folder: name) }
                    }
                }
                Divider()
                Button("New Folder…") {
                    folderTarget = bookmark
                    newFolderName = ""
                    isNamingFolder = true
                }
            }

            Button("Remove Bookmark", systemImage: "trash", role: .destructive) {
                remove(bookmark)
            }
        }
    }

    private func contextLine(_ bookmark: Bookmark) -> String {
        bookmark.groupTitle.isEmpty
            ? bookmark.pageTitle
            : "\(bookmark.pageTitle) · \(bookmark.groupTitle)"
    }

    // MARK: - Actions

    private func remove(_ bookmark: Bookmark) {
        withAnimation {
            modelContext.delete(bookmark)
            try? modelContext.save()
        }
    }

    private func assign(_ bookmark: Bookmark, folder: String?) {
        bookmark.folder = folder
        try? modelContext.save()
        statusMessage = folder.map { "Moved to \($0)." } ?? "Moved to Unfiled."
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        defer {
            newFolderName = ""
        }
        guard !name.isEmpty, let bookmark = folderTarget else {
            folderTarget = nil
            return
        }
        assign(bookmark, folder: name)
        folderTarget = nil
    }

    private func startExport() {
        exportDocument = BookmarkExportDocument(data: BookmarkArchive.encode(bookmarks.map(record(for:))))
        statusMessage = nil
        isExporting = true
    }

    private func record(for bookmark: Bookmark) -> BookmarkRecord {
        BookmarkRecord(
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

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let records = try BookmarkArchive.decode(Data(contentsOf: url))
            let outcome = importRecords(records)
            statusMessage = "Imported \(outcome.added) new, updated \(outcome.updated) existing."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Skips links that are already saved; reuses an imported folder for them.
    private func importRecords(_ records: [BookmarkRecord]) -> (added: Int, updated: Int) {
        let existing = (try? modelContext.fetch(FetchDescriptor<Bookmark>())) ?? []
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
            modelContext.insert(bookmark)
            byURL[record.url] = bookmark
            added += 1
        }

        withAnimation { try? modelContext.save() }
        return (added, updated)
    }
}

/// JSON document used by the share sheet.
struct BookmarkExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
