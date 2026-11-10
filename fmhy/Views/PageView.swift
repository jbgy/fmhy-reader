//
//  PageView.swift
//  fmhy
//
//  A single wiki section: categories -> groups -> entries, with a jump list
//  that scrolls to a category instead of filtering the page.
//

import SwiftUI

struct PageView: View {
    let slug: String

    @Environment(WikiStore.self) private var store
    @Environment(\.openWikiURL) private var openURL
    @State private var query = ""
    @State private var jumpTarget: String?
    @State private var showContents = false
    /// Id of the entry the arrow keys are on, so ↵ has something to open.
    @State private var keyEntry: String?

    private var definition: WikiPageDefinition? { WikiCatalog.bySlug[slug] }
    private var page: WikiPage? { store.pages[slug] }

    var body: some View {
        Group {
            if let page {
                if page.categories.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "doc.text",
                        description: Text("This section is empty in the current wiki snapshot.")
                    )
                } else {
                    pageList(page)
                }
            } else if store.loadingSlugs.contains(slug) {
                ProgressView("Loading \(definition?.title ?? "section")…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Couldn't load this section", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(
                        store.connection == .offline
                            ? "You're offline and this section isn't saved yet."
                            : "The wiki couldn't be reached."
                    )
                } actions: {
                    Button("Try Again") {
                        Task { await store.refreshPage(slug: slug) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(definition?.title ?? slug.capitalized)
        .task {
            await store.loadIfNeeded(slug: slug)
            store.recordVisit(slug: slug)
            // A section the wiki rewrites daily is worth re-checking on open;
            // one that changes monthly is not.
            await store.refreshIfStale(slug: slug)
        }
        .refreshable { await store.refreshPage(slug: slug) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showContents = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .disabled(page == nil)
                .help("Jump to a category")

                Button {
                    Task { await store.refreshPage(slug: slug) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.loadingSlugs.contains(slug) || store.isRefreshing)
                .help("Refresh this section")
            }
        }
        .sheet(isPresented: $showContents) {
            if let page {
                ContentsSheet(
                    categories: page.categories,
                    instanceURL: store.wikiURL(slug: slug),
                    jump: { jumpTarget = $0 }
                )
            }
        }
    }

    // MARK: - List

    private func pageList(_ page: WikiPage) -> some View {
        let categories = filtered(page)
        return ScrollViewReader { proxy in
            List {
                if store.connection == .offline {
                    Label("Offline — showing the saved copy", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let churn = store.churnDescription(for: slug) {
                    Label(churn, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                ForEach(categories) { category in
                    let groups = category.groups.filter(\.hasContent)
                    ForEach(groups) { group in
                        Section {
                            if group.id == groups.first?.id {
                                ForEach(category.notes, id: \.self) { note in
                                    WikiNoteText(text: note)
                                }
                            }
                            ForEach(group.notes, id: \.self) { note in
                                WikiNoteText(text: note)
                            }
                            ForEach(group.entries) { entry in
                                EntryRow(
                                    entry: entry,
                                    context: EntryContext(
                                        pageSlug: page.slug,
                                        pageTitle: definition?.title ?? page.title,
                                        categoryTitle: category.title,
                                        groupTitle: group.title
                                    )
                                )
                                .id(entry.id)
                                .listRowBackground(
                                    keyEntry == entry.id ? Color.accentColor.opacity(0.14) : nil
                                )
                            }
                        } header: {
                            header(
                                category: category,
                                group: group,
                                isFirst: group.id == groups.first?.id
                            )
                            .id(group.id)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .inlineSearchable(text: $query, prompt: "Search \(page.title)")
            .overlay {
                if categories.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                jumpTarget = nil
            }
            .onAppear { consumePendingJump(proxy, page: page) }
            .onChange(of: store.pendingJump) { _, _ in
                consumePendingJump(proxy, page: page)
            }
            // Keyboard walking: the arrows move a highlight through the links,
            // ↵ opens the highlighted one.
            .onKeyPress(.downArrow) {
                moveKeyEntry(1, page: page, proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveKeyEntry(-1, page: page, proxy: proxy)
                return .handled
            }
            .onKeyPress(.return) {
                openKeyEntry(page)
                return .handled
            }
        }
    }

    // MARK: - Keyboard

    /// Every link the list is currently showing, in display order.
    private func navigableEntries(_ page: WikiPage) -> [WikiEntry] {
        filtered(page).flatMap { category in
            category.groups.filter(\.hasContent).flatMap(\.entries)
        }
    }

    private func moveKeyEntry(_ delta: Int, page: WikiPage, proxy: ScrollViewProxy) {
        let entries = navigableEntries(page)
        guard !entries.isEmpty else { return }
        let current = keyEntry.flatMap { id in entries.firstIndex { $0.id == id } } ?? -1
        let next = (current + delta + entries.count) % entries.count
        keyEntry = entries[next].id
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(entries[next].id, anchor: .center)
        }
    }

    private func openKeyEntry(_ page: WikiPage) {
        guard let keyEntry,
              let entry = navigableEntries(page).first(where: { $0.id == keyEntry })
        else { return }
        openURL(entry.url)
    }

    /// Scrolls to the group a cross-reference link pointed at.
    private func consumePendingJump(_ proxy: ScrollViewProxy, page: WikiPage) {
        guard let pending = store.pendingJump, pending.slug == page.slug else { return }
        store.clearJump()
        guard let target = page.groupID(matching: pending.group) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func header(category: WikiCategory, group: WikiGroup, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if isFirst {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .textCase(nil)
            }
            if !group.title.isEmpty {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFirst ? Color.secondary : Color.primary)
                    .textCase(nil)
            }
        }
        .padding(.top, isFirst ? 8 : 2)
    }

    // MARK: - Filtering

    private func filtered(_ page: WikiPage) -> [WikiCategory] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return page.categories }

        return page.categories.compactMap { category in
            let groups: [WikiGroup] = category.groups.compactMap { group in
                let groupMatches = group.title.localizedCaseInsensitiveContains(query)
                    || category.title.localizedCaseInsensitiveContains(query)
                let entries = groupMatches
                    ? group.entries
                    : group.entries.filter {
                        $0.title.localizedCaseInsensitiveContains(query)
                            || $0.summary.localizedCaseInsensitiveContains(query)
                    }
                guard !entries.isEmpty else { return nil }
                return WikiGroup(
                    id: group.id,
                    title: group.title,
                    level: group.level,
                    notes: group.notes,
                    entries: entries
                )
            }
            guard !groups.isEmpty else { return nil }
            return WikiCategory(
                id: category.id,
                title: category.title,
                remote: category.remote,
                notes: category.notes,
                groups: groups
            )
        }
    }
}
