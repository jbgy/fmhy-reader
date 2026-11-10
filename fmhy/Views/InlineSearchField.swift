//
//  InlineSearchField.swift
//  fmhy
//
//  macOS filter fields.
//
//  SwiftUI's .searchable installs an item in the window's NSToolbar. When the
//  detail column swaps one searching view for another (Overview -> a section,
//  Search -> Bookmarks, and so on), AppKit receives a second insert for
//  com.apple.SwiftUI.search and throws, which kills the app. macOS screens
//  therefore filter with a plain field; iOS keeps the native search bar.
//

import SwiftUI

struct InlineSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(text: $text, prompt: Text(prompt)) {
            Text(prompt)
        }
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

extension View {
    /// Native search bar on iOS, inline filter field on macOS.
    @ViewBuilder
    func inlineSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(macOS)
        safeAreaInset(edge: .top, spacing: 0) {
            InlineSearchField(prompt: prompt, text: text)
        }
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }
}
