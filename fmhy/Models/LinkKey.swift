//
//  LinkKey.swift
//  fmhy
//
//  A saved link and a wiki entry point at the same page even when they differ
//  in the small ways that change nothing: a capitalised host, a trailing slash,
//  an anchor. Bookmarks are matched on this key so the audit does not call a
//  link removed over cosmetics.
//

import Foundation

enum LinkKey {
    static func of(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? trimmed
    }
}
