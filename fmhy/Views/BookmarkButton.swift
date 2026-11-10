//
//  BookmarkButton.swift
//  fmhy
//

import SwiftUI
import SwiftData

/// Star button that saves / removes an entry from the local SwiftData store.
struct BookmarkButton: View {
    let entry: WikiEntry
    let context: EntryContext

    @Environment(\.modelContext) private var modelContext
    @Query private var matches: [Bookmark]

    init(entry: WikiEntry, context: EntryContext) {
        self.entry = entry
        self.context = context
        let urlString = entry.url.absoluteString
        _matches = Query(filter: #Predicate<Bookmark> { $0.urlString == urlString })
    }

    private var isSaved: Bool { !matches.isEmpty }

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isSaved ? "star.fill" : "star")
                .font(.callout)
                .foregroundStyle(isSaved ? Color.yellow : Color.secondary.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isSaved ? "Remove bookmark" : "Save bookmark")
        .help(isSaved ? "Remove bookmark" : "Save bookmark")
    }

    private func toggle() {
        withAnimation(.snappy) {
            if let existing = matches.first {
                modelContext.delete(existing)
            } else {
                modelContext.insert(Bookmark(entry: entry, context: context))
            }
        }
        try? modelContext.save()
    }
}
