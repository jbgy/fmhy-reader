//
//  WikiNoteText.swift
//  fmhy
//
//  Wiki notes are prose with inline links, so parse them as markdown and send
//  link taps through the app's own router instead of the system browser.
//

import SwiftUI

struct WikiNoteText: View {
    let text: String

    @Environment(\.openWikiURL) private var openWikiURL

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        Text(attributed)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .tint(.accentColor)
            .environment(\.openURL, OpenURLAction { url in
                openWikiURL(url)
                return .handled
            })
    }
}
