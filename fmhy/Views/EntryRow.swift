//
//  EntryRow.swift
//  fmhy
//

import SwiftUI

struct EntryRow: View {
    let entry: WikiEntry
    let context: EntryContext
    var breadcrumb: String?
    /// When set, the breadcrumb becomes a button that opens that section in the app.
    var breadcrumbAction: (() -> Void)?

    @Environment(\.openWikiURL) private var openURL

    private var symbol: String {
        switch entry.kind {
        case .starred: "star.circle"
        case .index: "globe"
        case .crossLink: "arrow.uturn.right.circle"
        case .mention: "text.bubble"
        case .standard: "link"
        }
    }

    var body: some View {
        Button {
            // The trail is what makes a link found by browsing findable again
            // a week later; bookmarks are the deliberate version of the same.
            TrailStore.shared.record(entry, context: context)
            openURL(entry.url)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .frame(width: 16, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let breadcrumb {
                        if let breadcrumbAction {
                            Button(action: breadcrumbAction) {
                                HStack(spacing: 3) {
                                    Text(breadcrumb)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(breadcrumb) section")
                        } else {
                            Text(breadcrumb)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if !entry.summary.isEmpty {
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                BookmarkButton(entry: entry, context: context)
                    .padding(.top, -4)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "safari") { openURL(entry.url) }
            Button("Open in Default Browser", systemImage: "arrow.up.forward.app") {
                ExternalBrowser.open(entry.url)
            }
            Button("Copy Link", systemImage: "doc.on.doc") {
                Clipboard.copy(entry.url.absoluteString)
            }

            if let breadcrumbAction {
                Divider()
                Button("Go to Section", systemImage: "arrow.turn.down.right", action: breadcrumbAction)
            }

            if !entry.extraLinks.isEmpty {
                Divider()
                ForEach(entry.extraLinks) { link in
                    Button(link.title) { openURL(link.url) }
                }
            }
        }
    }
}
