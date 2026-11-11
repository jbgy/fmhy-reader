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
    /// nil leaves the header off a list that has no folders to tell apart.
    let title: String?
    let items: [Bookmark]
    var id: String { title ?? "" }
}

struct BookmarksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WikiStore.self) private var store
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
    @State private var importRequest: BookmarkImportRequest?
    /// Backed by the same defaults key as `BookmarkBackup`, so the menu and the
    /// footer redraw the moment the copy is turned on or off.
    @AppStorage(BookmarkBackup.enabledKey) private var backupEnabled = false

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

    /// Bookmarks whose own section is loaded and no longer lists the link:
    /// FMHY dropped them, so the list should say so instead of pretending the
    /// link is still part of the wiki.
    private var gone: [Bookmark] {
        bookmarks.filter { store.isGoneFromWiki(urlString: $0.urlString, slug: $0.pageSlug) }
    }

    private var sections: [BookmarkSection] {
        var buckets: [String: [Bookmark]] = [:]
        for bookmark in filtered {
            buckets[bookmark.folder ?? "", default: []].append(bookmark)
        }

        var result: [BookmarkSection] = []
        if let unfiled = buckets.removeValue(forKey: ""), !unfiled.isEmpty {
            // On its own the loose list needs no name: a lone "Unfiled" header
            // above every saved link reads like a folder the user never made.
            result.append(BookmarkSection(title: buckets.isEmpty ? nil : "Unfiled", items: unfiled))
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
                } actions: {
                    if let backup = BookmarkBackup.store.records() {
                        Button("Restore \(backup.count) from Backup") { beginRestore(backup) }
                    }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !gone.isEmpty {
                        Section {
                            Button(role: .destructive) {
                                removeGone()
                            } label: {
                                Label(
                                    "Remove \(gone.count) link\(gone.count == 1 ? "" : "s") no longer in FMHY",
                                    systemImage: "trash"
                                )
                            }
                        } footer: {
                            Text("FMHY dropped these from the wiki. They stay saved until you remove them.")
                        }
                    }

                    ForEach(sections) { section in
                        if let title = section.title {
                            Section(title) { rows(section.items) }
                        } else {
                            Section { rows(section.items) }
                        }
                    }

                    Section {} footer: {
                        Text(statusMessage ?? footerText)
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
        // A file or a backup holds whatever it holds; the reader picks which of
        // those links the list should adopt before anything is written.
        .sheet(item: $importRequest) { request in
            BookmarkImportView(
                request: request,
                existingURLs: Set(bookmarks.map(\.urlString)),
                onCancel: { importRequest = nil },
                onImport: { records in
                    apply(records, from: request)
                    importRequest = nil
                }
            )
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
            Divider()
            // A menu toggle only redraws its checkmark when an observed value
            // changes, so the action is spelled out instead.
            Button(
                backupEnabled ? "Turn Off Automatic Backup" : "Turn On Automatic Backup",
                systemImage: backupEnabled ? "externaldrive.badge.xmark" : "externaldrive.badge.checkmark"
            ) {
                backupEnabled.toggle()
                setBackup(backupEnabled)
            }
            if BookmarkBackup.store.exists, let backup = BookmarkBackup.store.records() {
                Button(
                    "Restore \(backup.count) Bookmark\(backup.count == 1 ? "" : "s") from Backup",
                    systemImage: "arrow.counterclockwise"
                ) {
                    beginRestore(backup)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("Bookmark folders, export and import")
    }

    // MARK: - Rows

    @ViewBuilder
    private func rows(_ items: [Bookmark]) -> some View {
        ForEach(items) { bookmark in
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

                    if store.isGoneFromWiki(urlString: bookmark.urlString, slug: bookmark.pageSlug) {
                        Label("No longer in FMHY", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
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
        BookmarkBackup.snapshot(in: modelContext)
    }

    private func removeGone() {
        let items = gone
        guard !items.isEmpty else { return }
        withAnimation {
            items.forEach(modelContext.delete)
            try? modelContext.save()
        }
        BookmarkBackup.snapshot(in: modelContext)
        statusMessage = "Removed \(items.count) link\(items.count == 1 ? "" : "s") the wiki no longer lists."
    }

    private func assign(_ bookmark: Bookmark, folder: String?) {
        bookmark.folder = folder
        try? modelContext.save()
        BookmarkBackup.snapshot(in: modelContext)
        statusMessage = folder.map { "Moved to \($0)." } ?? "Moved to Unfiled."
    }

    private var footerText: String {
        let saved = "\(bookmarks.count) saved"
        return backupEnabled
            ? "\(saved) · automatic backup on"
            : "\(saved) · stored only on this device"
    }

    /// Turning the copy on writes it right away; turning it off removes it.
    private func setBackup(_ enabled: Bool) {
        BookmarkBackup.isEnabled = enabled
        if enabled {
            BookmarkBackup.snapshot(in: modelContext)
            statusMessage = bookmarks.isEmpty
                ? "Backup on · a copy is written after the next bookmark."
                : "Backup on · \(bookmarks.count) bookmarks copied."
        } else {
            BookmarkBackup.store.remove()
            statusMessage = "Backup off · the copy was removed."
        }
    }

    private func beginRestore(_ records: [BookmarkRecord]) {
        statusMessage = nil
        importRequest = BookmarkImportRequest(records: records, source: .backup)
    }

    private func apply(_ records: [BookmarkRecord], from request: BookmarkImportRequest) {
        guard !records.isEmpty else {
            statusMessage = "Nothing was selected, so nothing changed."
            return
        }
        let outcome = withAnimation { BookmarkImport.merge(records, into: modelContext) }
        if request.source == .backup { BookmarkBackup.acceptRestore() }
        statusMessage = "Imported \(outcome.added) new, updated \(outcome.updated) existing."
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
        exportDocument = BookmarkExportDocument(data: BookmarkArchive.encode(bookmarks.map { BookmarkRecord(bookmark: $0) }))
        statusMessage = nil
        isExporting = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let records = try BookmarkArchive.decode(Data(contentsOf: url))
            guard !records.isEmpty else {
                statusMessage = "That file holds no bookmarks."
                return
            }
            statusMessage = nil
            importRequest = BookmarkImportRequest(records: records, source: .file)
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
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
