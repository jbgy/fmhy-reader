//
//  SettingsView.swift
//  fmhy
//
//  The choices that used to live in sidebar and bookmark menus, in one place.
//

import SwiftUI
import SwiftData

/// How the app should follow the system appearance.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Environment(WikiStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var bookmarks: [Bookmark]

    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @AppStorage("overviewHintDismissed") private var hintDismissed = false
    @AppStorage(WikiStore.autoRefreshKey) private var autoRefresh = true
    @AppStorage(BookmarkBackup.enabledKey) private var backupEnabled = false

    @State private var showDomainSheet = false

    var body: some View {
        Form {
            appearanceSection
            overviewSection
            updatesSection
            domainSection
            bookmarkSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(width: 480, height: 580)
        #endif
        .sheet(isPresented: $showDomainSheet) {
            InstanceSetupView(isFirstRun: false)
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            #if os(macOS)
            .pickerStyle(.segmented)
            #endif
        } footer: {
            Text("System follows the device. The tile grid, sidebar and text colours change with it.")
        }
    }

    private var overviewSection: some View {
        Section {
            Toggle(
                "Show the overview tip",
                isOn: Binding(
                    get: { !hintDismissed },
                    set: { hintDismissed = !$0 }
                )
            )
        } footer: {
            Text("The card explaining that the grid is an index, not the whole wiki.")
        }
    }

    private var updatesSection: some View {
        Section {
            Toggle("Check for wiki updates automatically", isOn: $autoRefresh)

            LabeledContent("Status") {
                Text(store.statusLine)
                    .foregroundStyle(.secondary)
            }

            if let commitLine = store.commitLine {
                LabeledContent("Wiki revision") {
                    Text(commitLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button("Check Now") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isRefreshing || store.needsInstanceSetup)

            if store.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.statusDetail ?? "Checking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(
                "Updates are free of API keys: the app reads FMHY's commit feed and downloads only "
                + "the sections that changed. Turning this off keeps the saved copy and leaves the "
                + "\"Check Now\" button working."
            )
        }
    }

    private var domainSection: some View {
        Section {
            LabeledContent("Domain") {
                Text(store.activeInstance?.host ?? store.preferredInstanceID)
                    .foregroundStyle(.secondary)
            }

            if let active = store.activeInstance, active.host != store.preferredInstanceID {
                LabeledContent("Fallback") {
                    Text(active.host)
                        .foregroundStyle(.orange)
                }
            }

            Toggle(
                "Fall back to a working mirror",
                isOn: Binding(
                    get: { store.autoFallback },
                    set: { store.setAutoFallback($0) }
                )
            )

            Button("Change Wiki Domain…") {
                showDomainSheet = true
            }
        } footer: {
            Text("Sections open on the chosen domain; the article text always comes from FMHY's GitHub source.")
        }
    }

    private var bookmarkSection: some View {
        Section {
            LabeledContent("Saved") {
                Text("\(bookmarks.count)")
                    .foregroundStyle(.secondary)
            }

            Toggle("Keep an automatic backup", isOn: $backupEnabled)
                .onChange(of: backupEnabled) { _, enabled in
                    applyBackup(enabled)
                }
        } footer: {
            Text(
                backupEnabled
                    ? "A JSON copy is written next to the app's documents, so a broken store or a "
                        + "reinstall does not lose the list. Visible in the Files app on iPhone."
                    : "Bookmarks live only in the app's database. A backup copy can refill an empty list later."
            )
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Sections") {
                Text(store.catalog.count.formatted())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Links") {
                Text(store.totalEntryCount.formatted())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Version") {
                Text(Self.version)
                    .foregroundStyle(.secondary)
            }

            Text("An unofficial reader for FMHY. Not affiliated with or endorsed by the FMHY team.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    /// The toggle and the bookmarks menu share one defaults key, so this only has
    /// to write or remove the copy itself.
    private func applyBackup(_ enabled: Bool) {
        BookmarkBackup.isEnabled = enabled
        if enabled {
            BookmarkBackup.snapshot(in: modelContext)
        } else {
            BookmarkBackup.store.remove()
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(WikiStore())
    .modelContainer(for: Bookmark.self, inMemory: true)
}
