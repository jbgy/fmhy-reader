//
//  RootView.swift
//  fmhy
//
//  Adaptive shell: sidebar + detail, which collapses into a stack on iPhone.
//

import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case overview
    case page(String)
    case search
    case bookmarks
}

struct RootView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarItem? = .overview
    @State private var browserSheet: BrowserSheet?
    @State private var showInstanceSheet = false

    private var instanceSheetPresented: Binding<Bool> {
        Binding(
            get: { showInstanceSheet || store.needsInstanceSetup },
            set: { showInstanceSheet = $0 }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, onChangeInstance: { showInstanceSheet = true })
                .navigationSplitViewColumnWidth(min: 230, ideal: 280)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.openSection, OpenSectionAction { slug, group in
            if let group {
                store.requestJump(WikiJump(slug: slug, group: group))
            }
            selection = .page(slug)
        })
        .environment(\.openWikiURL, OpenWikiURLAction { url in
            // Cross-references to FMHY itself stay in the app, and anchors that
            // point at a group scroll there instead of doing nothing.
            if let target = WikiLinkRouter.target(for: url) {
                if let group = target.group {
                    store.requestJump(WikiJump(slug: target.slug, group: group))
                }
                selection = .page(target.slug)
                return
            }
            #if os(iOS)
            browserSheet = BrowserSheet(url: url)
            #else
            ExternalBrowser.open(url)
            #endif
        })
        .sheet(item: $browserSheet) { sheet in
            SafariSheet(url: sheet.url)
        }
        .sheet(isPresented: instanceSheetPresented) {
            InstanceSetupView(isFirstRun: store.needsInstanceSetup)
                .interactiveDismissDisabled(store.needsInstanceSetup)
        }
        .task {
            // Launch always lands on the overview. Jumping straight into the
            // last section felt like the app navigating on its own, so reading
            // resumes from the overview's "Recently viewed" row instead.
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.refreshInstanceHealthIfStale()
                    await store.refreshIfNeeded()
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .page(let slug):
            PageView(slug: slug)
        case .search:
            SearchView()
        case .bookmarks:
            BookmarksView()
        case .overview, .none:
            OverviewView(selection: $selection, onChangeInstance: { showInstanceSheet = true })
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    var onChangeInstance: () -> Void

    @Environment(WikiStore.self) private var store
    @State private var filter = ""

    private var filteredPages: [WikiPageDefinition] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.catalog }
        return store.catalog.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Overview", systemImage: "rectangle.grid.2x2")
                    .tag(SidebarItem.overview)
                Label("Search Wiki", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
                Label("Bookmarks", systemImage: "star.fill")
                    .tag(SidebarItem.bookmarks)
            }

            Section("Wiki") {
                ForEach(filteredPages) { definition in
                    Label {
                        Text(definition.title)
                    } icon: {
                        Image(systemName: definition.symbol)
                            .foregroundStyle(.tint)
                    }
                    .tag(SidebarItem.page(definition.slug))
                    .contextMenu {
                        if let url = store.wikiURL(slug: definition.slug) {
                            Button("Open on \(store.activeInstance?.host ?? "FMHY")", systemImage: "safari") {
                                ExternalBrowser.open(url)
                            }
                        }
                    }
                }
            }

            Section {
                StatusRow(onChangeInstance: onChangeInstance)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FMHY")
        #if os(iOS)
        .searchable(
            text: $filter,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Filter sections"
        )
        #else
        // No .searchable here on macOS: the detail column adds its own, and two
        // search fields in one window toolbar make AppKit throw on launch
        // ("already contains an item with the identifier com.apple.SwiftUI.search").
        .safeAreaInset(edge: .top, spacing: 0) {
            InlineSearchField(prompt: "Filter sections", text: $filter)
        }
        #endif
    }
}

/// Update state plus the active domain, shown as the last sidebar row.
struct StatusRow: View {
    var onChangeInstance: () -> Void

    @Environment(WikiStore.self) private var store

    private var tint: Color {
        let host = store.activeInstance?.host ?? store.preferredInstanceID
        switch store.instanceHealth[host] {
        case .online: return Color.green
        case .offline: return Color.orange
        default: return Color.secondary
        }
    }

    /// Only shown when the chosen domain is down and a mirror took over.
    private var fallbackLine: String? {
        guard let active = store.activeInstance else { return "No domain chosen" }
        guard active.host != store.preferredInstanceID else { return nil }
        return "\(active.host) · fallback"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let commitLine = store.commitLine {
                    Text(commitLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let fallbackLine {
                    Text(fallbackLine)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }

            Menu {
                Button("Change Wiki Domain…") { onChangeInstance() }
                Divider()
                Button("Check for Updates") {
                    Task { await store.refreshAll() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .help("Domain: \(store.activeInstance?.host ?? "none chosen")")
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RootView()
        .environment(WikiStore())
        .modelContainer(for: Bookmark.self, inMemory: true)
}
