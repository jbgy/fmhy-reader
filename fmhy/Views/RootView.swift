//
//  RootView.swift
//  fmhy
//
//  Adaptive shell: sidebar + detail on iPad and Mac, a tab bar on iPhone and
//  wherever the sidebar is not on screen, so the four roots stay one tap away.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

enum SidebarItem: Hashable {
    case overview
    case page(String)
    case search
    case bookmarks
    case posts
    case settings
}

#if os(iOS)
/// A page pushed on top of an iPhone tab.
enum Route: Hashable {
    case page(String)
    case posts
}

enum PhoneTab: Hashable {
    case overview
    case search
    case bookmarks
    case settings
}
#endif

struct RootView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarItem? = .overview
    @State private var browserSheet: BrowserSheet?
    @State private var showInstanceSheet = false
    @State private var restoreRecords: [BookmarkRecord]?
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    #if os(iOS)
    @State private var phoneTab: PhoneTab = .overview
    @State private var overviewPath: [Route] = []
    @State private var searchPath: [Route] = []
    #endif
    @State private var showPalette = false
    /// The split view's own state: collapsing the sidebar on the Mac is what
    /// brings the tab bar in.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The tab kept lit while a section is open, the way pushing a page leaves
    /// its iPhone tab highlighted rather than clearing it.
    @State private var lastRoot: SidebarItem = .overview

    private var instanceSheetPresented: Binding<Bool> {
        Binding(
            get: { showInstanceSheet || store.needsInstanceSetup },
            set: { showInstanceSheet = $0 }
        )
    }

    var body: some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .environment(\.openSection, OpenSectionAction { slug, group in
                show(slug: slug, group: group)
            })
            .environment(\.openWikiURL, OpenWikiURLAction { url in
                openWikiURL(url)
            })
        .sheet(item: $browserSheet) { sheet in
            SafariSheet(url: sheet.url)
        }
        .sheet(isPresented: instanceSheetPresented) {
            InstanceSetupView(isFirstRun: store.needsInstanceSetup)
                .interactiveDismissDisabled(store.needsInstanceSetup)
        }
        // Restoring is a choice: declining leaves the empty list and the file as
        // they are, and the same copy is not offered again.
        .alert(
            restoreRecords.map { "Restore \($0.count) bookmarks?" } ?? "Restore bookmarks?",
            isPresented: Binding(
                get: { restoreRecords != nil },
                set: { if !$0 { restoreRecords = nil } }
            )
        ) {
            Button("Restore") { restoreBackup() }
            Button("Not Now", role: .cancel) { BookmarkBackup.declineRestore() }
        } message: {
            Text("An earlier backup copy can refill your empty bookmark list.")
        }
        .task {
            // Launch always lands on the overview. Jumping straight into the
            // last section felt like the app navigating on its own, so reading
            // resumes from the overview's "Recently viewed" row instead.
            await store.bootstrap()
            offerBackupRestore()
            await AppReleaseMonitor.shared.checkIfNeeded()
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

    /// iPhone gets a tab bar; iPad and Mac keep the sidebar.
    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            phoneTabs
        } else {
            split
        }
        #else
        split
        #endif
    }

    private var split: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, onChangeInstance: { showInstanceSheet = true })
                .navigationSplitViewColumnWidth(min: 230, ideal: 280)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPalette = true
                } label: {
                    Label("Search Everything", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: [.command])
                .help("Search every section and link (⌘K)")
            }
        }
        .onChange(of: selection) { _, item in
            // Opening a section leaves the tab it came from lit; picking a
            // different root moves the light there.
            if let item, case .page = item { return }
            lastRoot = item ?? .overview
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsTabBar {
                RootTabBar(selection: $selection, active: activeTab)
            }
        }
        .overlay {
            if showPalette {
                CommandPalette(
                    onOpenSection: { slug in show(slug: slug, group: nil) },
                    onOpenEntry: { result in openWikiURL(result.entry.url) },
                    onDismiss: { showPalette = false }
                )
            }
        }
    }

    /// The lit tab: the root that is showing, or — while a section is open —
    /// the root it was opened from.
    private var activeTab: SidebarItem {
        if let selection, case .page = selection { return lastRoot }
        return selection ?? .overview
    }

    /// iPhone draws the native bar; iPad always gets this one beside the
    /// sidebar's section list; the Mac gets it once the sidebar is collapsed.
    private var showsTabBar: Bool {
        #if os(macOS)
        columnVisibility == .detailOnly
        #else
        true
        #endif
    }

    #if os(iOS)
    private var phoneTabs: some View {
        TabView(selection: $phoneTab) {
            NavigationStack(path: $overviewPath) {
                OverviewView(
                    openSection: { show(slug: $0, group: nil) },
                    openPosts: { overviewPath.append(.posts) },
                    onChangeInstance: { showInstanceSheet = true }
                )
                .navigationDestination(for: Route.self) { destination($0) }
            }
            .tabItem {
                Label("Overview", systemImage: "rectangle.grid.2x2")
            }
            .tag(PhoneTab.overview)

            NavigationStack(path: $searchPath) {
                SearchView()
                    .navigationDestination(for: Route.self) { destination($0) }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(PhoneTab.search)

            NavigationStack {
                BookmarksView()
            }
            .tabItem {
                Label("Bookmarks", systemImage: "star.fill")
            }
            .tag(PhoneTab.bookmarks)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(PhoneTab.settings)
        }
    }

    /// A pushed page takes the whole screen: the tab bar only belongs on the
    /// four roots, so it slides away with the push and returns on the way back.
    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .page(let slug):
            PageView(slug: slug)
                .toolbar(.hidden, for: .tabBar)
        case .posts:
            PostsView()
                .toolbar(.hidden, for: .tabBar)
        }
    }
    #endif

    /// Opens a section in whichever shell is on screen: the detail column on iPad
    /// and Mac, a pushed page on the iPhone tab that asked for it.
    private func show(slug: String, group: String?) {
        if let group {
            store.requestJump(WikiJump(slug: slug, group: group))
        }
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            if phoneTab == .search {
                searchPath.append(.page(slug))
            } else {
                phoneTab = .overview
                overviewPath.append(.page(slug))
            }
            return
        }
        #endif
        selection = .page(slug)
    }

    /// Cross-references to FMHY itself stay in the app, and anchors that point at
    /// a group scroll there instead of doing nothing.
    private func openWikiURL(_ url: URL) {
        if let target = WikiLinkRouter.target(for: url) {
            show(slug: target.slug, group: target.group)
            return
        }
        #if os(iOS)
        browserSheet = BrowserSheet(url: url)
        #else
        ExternalBrowser.open(url)
        #endif
    }

    private func offerBackupRestore() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Bookmark>())) ?? 0
        restoreRecords = BookmarkBackup.restoreCandidate(bookmarkCount: count)
    }

    private func restoreBackup() {
        guard let records = restoreRecords else { return }
        withAnimation { BookmarkImport.merge(records, into: modelContext) }
        BookmarkBackup.acceptRestore()
        restoreRecords = nil
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
        case .posts:
            PostsView()
        case .settings:
            SettingsView()
        case .overview, .none:
            OverviewView(
                openSection: { selection = .page($0) },
                openPosts: { selection = .posts },
                onChangeInstance: { showInstanceSheet = true }
            )
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

    /// Everything the list shows, in order, so the arrow keys can walk it.
    private var keyboardOrder: [SidebarItem] {
        var items: [SidebarItem] = filteredPages.map { .page($0.slug) }
        #if os(macOS)
        items.append(contentsOf: [.overview, .search, .bookmarks])
        #endif
        return items
    }

    private func moveSelection(_ delta: Int) {
        let items = keyboardOrder
        guard !items.isEmpty else { return }
        let current = items.firstIndex(of: selection ?? .overview) ?? 0
        selection = items[(current + delta + items.count) % items.count]
    }

    var body: some View {
        List(selection: $selection) {
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

            // On the Mac the library sits below the wiki so the sections read
            // first. iPad reaches these through the tab bar instead, so the
            // sidebar stays a list of sections rather than repeating them.
            #if os(macOS)
            Section("Library") {
                Label("Overview", systemImage: "rectangle.grid.2x2")
                    .tag(SidebarItem.overview)
                Label("Search Wiki", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
                Label("Bookmarks", systemImage: "star.fill")
                    .tag(SidebarItem.bookmarks)
            }
            #endif

            Section {
                StatusRow(onChangeInstance: onChangeInstance)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FMHY")
        .modifier(SidebarKeyboardNavigation(move: moveSelection))
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

/// The four app-level destinations, drawn as a tab bar. It writes the same
/// selection the sidebar does, so a tap moves the sidebar highlight and an
/// arrow-key move highlights the matching tab.
struct RootTabBar: View {
    @Binding var selection: SidebarItem?
    /// The tab to draw as lit. Opening a section keeps the tab it was opened
    /// under lit, the way the iPhone bar stays put when a page is pushed.
    var active: SidebarItem

    private struct Tab: Identifiable {
        let item: SidebarItem
        let title: String
        let symbol: String
        var id: SidebarItem { item }
    }

    private var tabs: [Tab] {
        var tabs = [
            Tab(item: .overview, title: "Overview", symbol: "rectangle.grid.2x2"),
            Tab(item: .search, title: "Search", symbol: "magnifyingglass"),
            Tab(item: .bookmarks, title: "Bookmarks", symbol: "star.fill")
        ]
        #if !os(macOS)
        // macOS gets the standard Settings window (⌘,) instead.
        tabs.append(Tab(item: .settings, title: "Settings", symbol: "gearshape"))
        #endif
        return tabs
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab.item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .regular))
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(active == tab.item ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active == tab.item ? [.isSelected] : [])
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Arrow-key movement for the sidebar. macOS lists already do this natively, so
/// it is only attached where a hardware keyboard meets a list that does not.
private struct SidebarKeyboardNavigation: ViewModifier {
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .focusable()
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
        #else
        content
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
