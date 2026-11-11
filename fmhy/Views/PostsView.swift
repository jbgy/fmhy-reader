//
//  PostsView.swift
//  fmhy
//
//  FMHY's own monthly update posts, read in the app instead of the website.
//

import SwiftUI

struct PostsView: View {
    @Environment(WikiStore.self) private var store
    @Environment(FMHYPostsStore.self) private var posts

    private var host: String {
        store.activeInstance?.host ?? WikiInstances.mainID
    }

    private var years: [Int] {
        let calendar = Calendar(identifier: .gregorian)
        return Set(posts.posts.map { calendar.component(.year, from: $0.published) }).sorted(by: >)
    }

    var body: some View {
        Group {
            if posts.posts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Posts")
        .task { await posts.loadIfNeeded(host: host) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await posts.refresh(host: host) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(posts.isLoading)
                .help("Reload FMHY's posts")
            }
        }
    }

    private var list: some View {
        let calendar = Calendar(identifier: .gregorian)
        return List {
            ForEach(years, id: \.self) { year in
                Section(String(year)) {
                    ForEach(posts.posts.filter { calendar.component(.year, from: $0.published) == year }) { post in
                        // The destination rides on the link rather than a
                        // `navigationDestination` on this screen: the modifier
                        // sits on content that swaps when the posts arrive, and
                        // the rows then opened nothing.
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(post.title)
                                    .font(.callout.weight(.semibold))
                                Text(post.published.formatted(.dateTime.day().month(.wide)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let excerpt = post.excerpt {
                                    Text(excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .refreshable { await posts.refresh(host: host) }
    }

    private var emptyState: some View {
        Group {
            if posts.isLoading {
                ProgressView("Loading posts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Posts Yet", systemImage: "newspaper")
                } description: {
                    Text(posts.error ?? "FMHY's monthly update posts will appear here.")
                } actions: {
                    Button("Try Again") {
                        Task { await posts.refresh(host: host) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct PostDetailView: View {
    let post: FMHYPost

    @Environment(\.openWikiURL) private var openWiki

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(post.published.formatted(.dateTime.day().month(.wide).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                ForEach(Array(post.blocks.enumerated()), id: \.offset) { _, block in
                    row(block)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .environment(\.openURL, OpenURLAction { url in
                openWiki(url)
                return .handled
            })
        }
        .navigationTitle(post.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = URL(string: post.link) {
                        ExternalBrowser.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open on the wiki")
            }
        }
    }

    @ViewBuilder
    private func row(_ block: PostBlock) -> some View {
        switch block.kind {
        case .heading:
            Text(inline(block.text))
                .font(.subheadline.weight(.semibold))
                .padding(.top, 10)
        case .paragraph:
            Text(inline(block.text))
                .font(.callout)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(inline(block.text))
                    .font(.callout)
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack {
        PostsView()
            .environment(WikiStore())
            .environment(FMHYPostsStore())
    }
}
