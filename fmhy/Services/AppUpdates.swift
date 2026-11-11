//
//  AppUpdates.swift
//  fmhy
//
//  Reads the app's own AltStore feed so the reader learns about a new build.
//  The app is sideloaded, so nothing else tells them a release happened.
//

import Foundation
import Observation

/// One release row from `docs/apps.json`.
struct AppRelease: Equatable, Sendable {
    let version: String
    let build: String
    let notes: String?
    let downloadURL: URL?

    var versionLine: String { "\(version) (\(build))" }
}

enum AppReleaseFeed {
    static let url = URL(string: "https://raw.githubusercontent.com/jbgy/fmhy-reader/refs/heads/main/docs/apps.json")!
    /// Where the readme for a build lives; a tap explains what changed.
    static let releasesURL = URL(string: "https://github.com/jbgy/fmhy-reader/releases/latest")!

    /// What this copy reports, from the bundle rather than from the feed.
    static var current: (version: String, build: String) {
        let info = Bundle.main.infoDictionary
        return (
            info?["CFBundleShortVersionString"] as? String ?? "0",
            info?["CFBundleVersion"] as? String ?? "0"
        )
    }

    private struct Payload: Decodable {
        struct App: Decodable {
            let version: String
            let buildVersion: String?
            let localizedDescription: String?
            let downloadURL: String?
        }

        let apps: [App]
    }

    /// The newest row in the feed. Rows arrive newest first, but the version
    /// numbers decide, so a re-ordered feed still reports the right release.
    static func latest(in data: Data) throws -> AppRelease? {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.apps
            .compactMap { app -> AppRelease? in
                guard AppVersion(app.version) != nil else { return nil }
                return AppRelease(
                    version: app.version,
                    build: app.buildVersion ?? "0",
                    notes: app.localizedDescription,
                    downloadURL: app.downloadURL.flatMap(URL.init(string:))
                )
            }
            .max { isOlder($0, than: $1) }
    }

    /// True when the feed's release is ahead of the running copy. The version
    /// decides first, so 2.0.1 beats 2.0 even when the build numbers collide,
    /// and the build number settles a republished version.
    static func isNewer(_ release: AppRelease, thanVersion version: String, build: String) -> Bool {
        guard let remote = AppVersion(release.version) else { return false }
        if let local = AppVersion(version), remote != local {
            return remote > local
        }
        return (Int(release.build) ?? 0) > (Int(build) ?? 0)
    }

    private static func isOlder(_ lhs: AppRelease, than rhs: AppRelease) -> Bool {
        guard let left = AppVersion(lhs.version), let right = AppVersion(rhs.version) else {
            return false
        }
        if left != right { return left < right }
        return (Int(lhs.build) ?? 0) < (Int(rhs.build) ?? 0)
    }
}

/// A dotted version compared number by number, so 2.0.1 sits above 2.0 and
/// 2.10 above 2.9. Trailing zeros do not matter.
struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// Checks the feed at most every few hours, quietly: a failed request is not
/// something the reader needs to see.
@MainActor
@Observable
final class AppReleaseMonitor {
    static let shared = AppReleaseMonitor()

    private(set) var available: AppRelease?
    private(set) var checkedAt: Date?
    private(set) var isChecking = false

    private static let checkInterval: TimeInterval = 6 * 60 * 60

    func checkIfNeeded() async {
        if let checkedAt, Date().timeIntervalSince(checkedAt) < Self.checkInterval { return }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: AppReleaseFeed.url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("FMHY-wiki-app", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let latest = try? AppReleaseFeed.latest(in: data)
        else { return }

        checkedAt = .now
        let current = AppReleaseFeed.current
        available = AppReleaseFeed.isNewer(
            latest,
            thanVersion: current.version,
            build: current.build
        ) ? latest : nil
    }
}
