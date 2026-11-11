//
//  BookmarkImportView.swift
//  fmhy
//
//  Review step for bookmarks arriving from a file or the backup copy: only the
//  links ticked here reach the list.
//

import SwiftUI

/// One incoming list, held until the reader picks from it.
struct BookmarkImportRequest: Identifiable {
    enum Source {
        case file
        case backup
    }

    let id = UUID()
    let records: [BookmarkRecord]
    let source: Source
}

struct BookmarkImportView: View {
    let request: BookmarkImportRequest
    let existingURLs: Set<String>
    var onCancel: () -> Void
    var onImport: ([BookmarkRecord]) -> Void

    @State private var selected: Set<String>

    init(
        request: BookmarkImportRequest,
        existingURLs: Set<String>,
        onCancel: @escaping () -> Void,
        onImport: @escaping ([BookmarkRecord]) -> Void
    ) {
        self.request = request
        self.existingURLs = existingURLs
        self.onCancel = onCancel
        self.onImport = onImport
        _selected = State(initialValue: Set(request.records.map(\.url)))
    }

    private var newCount: Int {
        request.records.filter { !existingURLs.contains($0.url) }.count
    }

    private var existingCount: Int { request.records.count - newCount }

    private var chosen: [BookmarkRecord] {
        request.records.filter { selected.contains($0.url) }
    }

    private var allSelected: Bool { selected.count == request.records.count }

    private var summary: String {
        var parts = ["\(newCount) new"]
        if existingCount > 0 {
            parts.append("\(existingCount) already saved")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                ForEach(request.records, id: \.url) { record in
                    row(record)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif

            footer
        }
        #if os(macOS)
        .frame(width: 460, height: 540)
        #endif
    }

    private var title: String {
        switch request.source {
        case .file: "Import bookmarks"
        case .backup: "Restore from backup"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func row(_ record: BookmarkRecord) -> some View {
        Toggle(
            isOn: Binding(
                get: { selected.contains(record.url) },
                set: { keep in
                    if keep {
                        selected.insert(record.url)
                    } else {
                        selected.remove(record.url)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .lineLimit(2)
                Text(context(record))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
    }

    /// Where the link came from and where it would land, so a list of a dozen
    /// similar names can still be told apart.
    private func context(_ record: BookmarkRecord) -> String {
        var parts: [String] = []
        if let folder = record.folder, !folder.isEmpty {
            parts.append(folder)
        }
        if !record.pageTitle.isEmpty {
            parts.append(record.pageTitle)
        }
        parts.append(existingURLs.contains(record.url) ? "already saved" : record.url)
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(allSelected ? "Select None" : "Select All") {
                selected = allSelected ? [] : Set(request.records.map(\.url))
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 8)

            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Import \(chosen.count)") { onImport(chosen) }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
        }
        .padding(16)
    }
}

#Preview {
    BookmarkImportView(
        request: BookmarkImportRequest(
            records: [
                BookmarkRecord(url: "https://firefox.com", title: "Firefox", pageTitle: "Internet Tools"),
                BookmarkRecord(url: "https://mpv.io", title: "mpv", folder: "Players"),
            ],
            source: .file
        ),
        existingURLs: ["https://mpv.io"],
        onCancel: {},
        onImport: { _ in }
    )
}
