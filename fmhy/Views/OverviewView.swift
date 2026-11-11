//
//  OverviewView.swift
//  fmhy
//
//  Grid of every section, used as the start screen and as "Overview".
//

import SwiftUI

struct OverviewView: View {
    var openSection: (String) -> Void
    var openPosts: () -> Void
    var openTrail: () -> Void
    var onChangeInstance: () -> Void

    @Environment(WikiStore.self) private var store
    @Environment(\.openWikiURL) private var openURL
    private let trail = TrailStore.shared
    @AppStorage("overviewHintDismissed") private var hintDismissed = false
    private let releases = AppReleaseMonitor.shared

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if !hintDismissed, !store.needsInstanceSetup {
                    hint
                }

                if store.hasUpdateDigest {
                    whatsNew
                }

                if !store.recentSlugs.isEmpty {
                    recentlyViewed
                }

                if !trail.entries.isEmpty {
                    trailRow
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.catalog) { definition in
                        Button {
                            openSection(definition.slug)
                        } label: {
                            tile(definition)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("FMHY")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)

                // The navigation bar already shows the name in large type, so
                // the hero carries only the tagline.
                Text("The largest collection of free stuff on the internet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            chips
        }
    }

    /// One row while it fits, then two, then one chip per row. Without this the
    /// row's width pushes the whole page wider than the screen at large text.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                countChips
                postsChip
                domainChip
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    countChips
                    postsChip
                }
                domainChip
            }

            VStack(alignment: .leading, spacing: 8) {
                countChips
                postsChip
                domainChip
            }
        }
        // Metadata, not body copy: the cap keeps the widest single chip inside
        // a phone screen even at the largest accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var countChips: some View {
        infoChip("\(store.catalog.count) sections")
        // A zero count is only ever the moment before the cache loads.
        if store.totalEntryCount > 0 {
            infoChip("\(store.totalEntryCount) links")
        }
        // Sideloaded builds are never updated by the App Store, so the feed
        // has to say it here.
        if let release = releases.available {
            updateChip(release)
        }
    }

    private func updateChip(_ release: AppRelease) -> some View {
        Button {
            ExternalBrowser.open(AppReleaseFeed.releasesURL)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text("\(release.version) available")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.tint.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("A newer build is on the releases page")
    }

    /// FMHY's monthly update posts.
    private var postsChip: some View {
        Button {
            openPosts()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                    .font(.system(size: 8, weight: .semibold))
                Text("Posts")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.tint.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Monthly posts from FMHY")
    }

    private var domainChip: some View {
        Button(action: onChangeInstance) {
            HStack(spacing: 5) {
                Circle()
                    .fill(instanceTint)
                    .frame(width: 6, height: 6)
                Text(store.activeInstance?.host ?? store.preferredInstanceID)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Change wiki domain")
    }

    private var changedSections: [(slug: String, title: String, count: Int)] {
        store.updateDigest
            .compactMap { slug, count -> (slug: String, title: String, count: Int)? in
                guard let definition = WikiCatalog.bySlug[slug] else { return nil }
                return (slug, definition.title, count)
            }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }

    /// Sections the last silent update touched, with how many links each gained.
    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("New links since the last update", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(changedSections, id: \.slug) { item in
                        Button {
                            openSection(item.slug)
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("+\(item.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tint)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.tint.opacity(0.12), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The links opened lately, so a tool tried earlier is one tap away.
    private var trailRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Trail")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("See all") { openTrail() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trail.entries.prefix(5)) { item in
                        Button {
                            if let url = item.url { openURL(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.pageTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Jump back into whatever was read last.
    private var recentlyViewed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently viewed")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.recentSlugs.compactMap { WikiCatalog.bySlug[$0] }) { definition in
                        Button {
                            openSection(definition.slug)
                        } label: {
                            Label(definition.title, systemImage: definition.symbol)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary.opacity(0.5), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Explains that the grid is a table of contents, not the whole wiki.
    private var hint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("This is just the index")
                    .font(.footnote.weight(.semibold))
                Text("Tap a section to open it — every tile holds dozens of links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { hintDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(12)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    private var instanceTint: Color {
        let host = store.activeInstance?.host ?? store.preferredInstanceID
        switch store.instanceHealth[host] {
        case .online: return Color.green
        case .offline: return Color.orange
        default: return Color.secondary
        }
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: .capsule)
    }

    // MARK: - Tiles

    private func tile(_ definition: WikiPageDefinition) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: definition.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.13), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(definition.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle(definition))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            if store.newLinkCount(for: definition.slug) > 0 {
                Circle()
                    .fill(.tint)
                    .frame(width: 7, height: 7)
                    .padding(10)
                    .accessibilityLabel("New links")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func subtitle(_ definition: WikiPageDefinition) -> String {
        if let page = store.pages[definition.slug], page.entryCount > 0 {
            return "\(page.entryCount) links"
        }
        return definition.tagline
    }
}

#Preview {
    OverviewView(openSection: { _ in }, openPosts: {}, openTrail: {}, onChangeInstance: {})
        .environment(WikiStore())
}
