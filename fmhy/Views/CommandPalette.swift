//
//  CommandPalette.swift
//  fmhy
//
//  ⌘K on the Mac: one field for every section and every link in the wiki.
//

#if os(macOS)
import SwiftUI

struct CommandPalette: View {
    var onOpenSection: (String) -> Void
    var onOpenEntry: (SearchItem) -> Void
    var onDismiss: () -> Void

    @Environment(WikiStore.self) private var store
    @State private var query = ""
    @State private var active = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        enum Action {
            case section(String)
            case entry(SearchItem)
        }

        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let action: Action
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
                .padding(.top, 90)
                .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            field
            Divider()

            if items.isEmpty {
                emptyState
            } else {
                results
            }

            Divider()
            footer
        }
        .frame(width: 620)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary)
        }
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .onChange(of: query) { _, _ in
            active = 0
        }
        .task {
            // The window has to be on screen before the field can take focus.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("Search sections and every link", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit(openActive)
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Text("esc")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 4))
        }
        .padding(14)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 330)
    }

    private func row(_ item: Item, index: Int) -> some View {
        let isActive = index == active
        return Button {
            open(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Text(item.subtitle)
                        .font(.caption2)
                        .opacity(0.75)
                }

                Spacer(minLength: 8)

                if isActive {
                    Text("↵")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear),
                in: .rect(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { active = index }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(trimmed.isEmpty ? "Nothing to show yet" : "No matches for “\(trimmed)”")
                .font(.callout.weight(.semibold))
            Text(
                trimmed.isEmpty
                    ? "Start typing a section or the name of a tool."
                    : "Try a shorter word, or a domain like github.com."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ move   ·   ↵ open   ·   esc close")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(items.count) result\(items.count == 1 ? "" : "s")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var items: [Item] {
        let sections = matchingSections
        guard !trimmed.isEmpty else { return sections }

        let ranked = WikiSearch.rank(store.searchIndex, query: trimmed, limit: 8)
        let entries = ranked.enumerated().map { index, result in
            Item(
                id: "entry-\(index)-\(result.pageSlug)-\(result.entry.title)",
                title: result.entry.title,
                subtitle: result.groupTitle.isEmpty
                    ? result.pageTitle
                    : "\(result.pageTitle) · \(result.groupTitle)",
                symbol: "link",
                action: .entry(result)
            )
        }
        return sections + entries
    }

    /// Recent sections when the field is empty, matching ones once there is a query.
    private var matchingSections: [Item] {
        let definitions: [WikiPageDefinition]
        if trimmed.isEmpty {
            let recent = store.recentSlugs.compactMap { WikiCatalog.bySlug[$0] }
            definitions = recent.isEmpty ? Array(store.catalog.prefix(6)) : recent
        } else {
            definitions = Array(
                store.catalog
                    .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
                    .prefix(4)
            )
        }
        return definitions.map(sectionItem)
    }

    private func sectionItem(_ definition: WikiPageDefinition) -> Item {
        let count = store.pages[definition.slug]?.entryCount ?? 0
        return Item(
            id: "section-\(definition.slug)",
            title: definition.title,
            subtitle: count > 0 ? "Section · \(count.formatted()) links" : "Section",
            symbol: definition.symbol,
            action: .section(definition.slug)
        )
    }

    // MARK: - Interaction

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        active = (active + delta + items.count) % items.count
    }

    private func openActive() {
        guard items.indices.contains(active) else { return }
        open(items[active])
    }

    private func open(_ item: Item) {
        switch item.action {
        case .section(let slug):
            onOpenSection(slug)
        case .entry(let result):
            onOpenEntry(result)
        }
        onDismiss()
    }
}
#endif
