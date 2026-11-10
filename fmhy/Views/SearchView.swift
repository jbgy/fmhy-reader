//
//  SearchView.swift
//  fmhy
//
//  Searches every cached section. Works fully offline.
//

import SwiftUI

struct SearchView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.openSection) private var openSection
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var results: [SearchItem] {
        guard trimmedQuery.count >= 2 else { return [] }
        return WikiSearch.rank(store.searchIndex, query: trimmedQuery)
    }

    var body: some View {
        Group {
            if trimmedQuery.count < 2 {
                ContentUnavailableView {
                    Label("Search FMHY", systemImage: "magnifyingglass")
                } description: {
                    Text("Look through \(store.totalEntryCount) links across \(store.pages.count) sections, all stored on this device.")
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    Section {
                        ForEach(results) { item in
                            EntryRow(
                                entry: item.entry,
                                context: EntryContext(
                                    pageSlug: item.pageSlug,
                                    pageTitle: item.pageTitle,
                                    categoryTitle: item.categoryTitle,
                                    groupTitle: item.groupTitle
                                ),
                                breadcrumb: contextLine(item),
                                breadcrumbAction: {
                                    openSection(item.pageSlug, group: item.groupTitle)
                                }
                            )
                        }
                    } header: {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Sites, tools, groups…")
    }

    private func contextLine(_ item: SearchItem) -> String {
        item.groupTitle.isEmpty
            ? item.pageTitle
            : "\(item.pageTitle) · \(item.groupTitle)"
    }
}
