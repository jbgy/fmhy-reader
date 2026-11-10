//
//  ContentsSheet.swift
//  fmhy
//
//  Jump list for a section: taps scroll the page instead of filtering it.
//

import SwiftUI

struct ContentsSheet: View {
    let categories: [WikiCategory]
    let instanceURL: URL?
    let jump: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var visible: [WikiCategory] {
        categories.compactMap { category in
            let groups = category.groups.filter { !$0.entries.isEmpty }
            guard !groups.isEmpty else { return nil }
            guard !trimmed.isEmpty else {
                return WikiCategory(
                    id: category.id,
                    title: category.title,
                    remote: category.remote,
                    notes: [],
                    groups: groups.map { group in
                        WikiGroup(id: group.id, title: group.title, level: group.level, notes: [], entries: group.entries)
                    }
                )
            }
            let categoryMatches = category.title.localizedCaseInsensitiveContains(trimmed)
            let matchingGroups = categoryMatches ? groups : groups.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
            }
            guard !matchingGroups.isEmpty else { return nil }
            return WikiCategory(
                id: category.id,
                title: category.title,
                remote: category.remote,
                notes: [],
                groups: matchingGroups.map { group in
                    WikiGroup(id: group.id, title: group.title, level: group.level, notes: [], entries: group.entries)
                }
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { category in
                    Section {
                        ForEach(category.groups) { group in
                            Button {
                                jump(group.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Text(group.title.isEmpty ? "General" : group.title)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Text("\(group.entries.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(category.title)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Jump To")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Category or language")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if let instanceURL {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            ExternalBrowser.open(instanceURL)
                            dismiss()
                        } label: {
                            Label("Open on the wiki", systemImage: "safari")
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
