//
//  TrailView.swift
//  fmhy
//
//  Every link opened in the past week, newest first and grouped by day.
//

import SwiftUI

struct TrailView: View {
    @Environment(\.openWikiURL) private var openURL

    private let trail = TrailStore.shared

    private struct Day: Identifiable {
        let date: Date
        let items: [TrailEntry]

        var id: Date { date }
    }

    private var days: [Day] {
        let calendar = Calendar(identifier: .gregorian)
        var buckets: [Date: [TrailEntry]] = [:]
        for item in trail.entries {
            let day = calendar.startOfDay(for: item.openedAt)
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { Day(date: $0, items: buckets[$0] ?? []) }
    }

    var body: some View {
        Group {
            if trail.entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on the trail", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Links you open from a section land here for a week, so you can find them again without saving them.")
                }
            } else {
                List {
                    ForEach(days) { day in
                        Section(dayTitle(day.date)) {
                            ForEach(day.items) { item in
                                row(item)
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .navigationTitle("Trail")
        .toolbar {
            if !trail.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { trail.clear() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear the trail")
                }
            }
        }
    }

    private func row(_ item: TrailEntry) -> some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(contextLine(item))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                Text(item.openedAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url = item.url {
                Button("Open", systemImage: "safari") { openURL(url) }
                Button("Open in Default Browser", systemImage: "arrow.up.forward.app") {
                    ExternalBrowser.open(url)
                }
                Button("Copy Link", systemImage: "doc.on.doc") {
                    Clipboard.copy(url.absoluteString)
                }
            }
        }
    }

    private func contextLine(_ item: TrailEntry) -> String {
        item.pageTitle.isEmpty ? item.pageSlug : item.pageTitle
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
