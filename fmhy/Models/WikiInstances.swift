//
//  WikiInstances.swift
//  fmhy
//
//  Domains taken from https://fmhy.net/other/backups.
//  Only original-style instances are listed: "FMHY X" and "Retro FMHY" are
//  deliberately left out because they restyle the wiki.
//

import Foundation

struct WikiInstance: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case main
        case officialMirror
        case verified

        var badge: String {
            switch self {
            case .main: "Main site"
            case .officialMirror: "Official mirror"
            case .verified: "Verified mirror"
            }
        }
    }

    let host: String
    let kind: Kind
    var note: String?

    var id: String { host }
    var baseURL: URL { URL(string: "https://" + host)! }
}

enum WikiInstances {
    static let all: [WikiInstance] = [
        .init(host: "fmhy.net", kind: .main),
        .init(host: "fmhy.pages.dev", kind: .officialMirror),
        .init(host: "fmhyclone.pages.dev", kind: .officialMirror),
        .init(host: "fmhy.samidy.com", kind: .verified),
        .init(host: "fmhy.jbugel.xyz", kind: .verified),
        .init(host: "fmhy.ou0.cc", kind: .verified),
        .init(host: "fmhy.jvbf.dev", kind: .verified),
        .init(host: "fmhy.vencat.dev", kind: .verified),
        .init(host: "a-fmhy.pages.dev", kind: .verified),
        .init(host: "fmhy.artistgrid.cx", kind: .verified),
        .init(host: "fmhy.hoffnungfuerdiezukunft.net", kind: .verified),
        .init(host: "fmhy.xyz", kind: .verified, note: "Safe for work, no NSFW page"),
    ]

    static let mainID = "fmhy.net"

    static func instance(for host: String) -> WikiInstance? {
        all.first { $0.host == host }
    }
}

enum InstanceHealth: Equatable, Sendable {
    case checking
    case online
    case offline
}
