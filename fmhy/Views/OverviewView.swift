//
//  OverviewView.swift
//  fmhy
//
//  Grid of every section, used as the start screen and as "Overview".
//

import SwiftUI

struct OverviewView: View {
    @Binding var selection: SidebarItem?
    var onChangeInstance: () -> Void

    @Environment(WikiStore.self) private var store
    @AppStorage("overviewHintDismissed") private var hintDismissed = false

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

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.catalog) { definition in
                        Button {
                            selection = .page(definition.slug)
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
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FMHY")
                        .font(.largeTitle.weight(.bold))
                    Text("The largest collection of free stuff on the internet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                infoChip("\(store.catalog.count) sections")
                infoChip("\(store.totalEntryCount) links")

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
        }
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
                            selection = .page(item.slug)
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
                            selection = .page(definition.slug)
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
    OverviewView(selection: .constant(.overview), onChangeInstance: {})
        .environment(WikiStore())
}
