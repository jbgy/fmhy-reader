//
//  SafariView.swift
//  fmhy
//
//  In-app browser on iOS/iPadOS, default browser on macOS.
//

import SwiftUI

#if os(iOS)
import SafariServices
import UIKit

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

/// Identifiable URL wrapper for `.sheet(item:)`.
struct BrowserSheet: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariSheet: View {
    let url: URL

    var body: some View {
        #if os(iOS)
        SafariView(url: url)
            .ignoresSafeArea()
        #else
        VStack(spacing: 16) {
            Image(systemName: "safari")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .multilineTextAlignment(.center)
            Button("Open in Browser") { ExternalBrowser.open(url) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 380, minHeight: 220)
        #endif
    }
}

enum ExternalBrowser {
    @MainActor
    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

enum Clipboard {
    @MainActor
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

// MARK: - Environment plumbing

struct OpenWikiURLAction {
    let action: (URL) -> Void

    func callAsFunction(_ url: URL) {
        action(url)
    }
}

/// Opens a wiki section inside the app, optionally scrolling to a group.
struct OpenSectionAction {
    let action: (_ slug: String, _ group: String?) -> Void

    func callAsFunction(_ slug: String, group: String? = nil) {
        action(slug, group)
    }
}

private struct OpenSectionKey: EnvironmentKey {
    static let defaultValue = OpenSectionAction { _, _ in }
}

extension EnvironmentValues {
    var openSection: OpenSectionAction {
        get { self[OpenSectionKey.self] }
        set { self[OpenSectionKey.self] = newValue }
    }
}

private struct OpenWikiURLKey: EnvironmentKey {
    static let defaultValue = OpenWikiURLAction { url in
        Task { @MainActor in
            ExternalBrowser.open(url)
        }
    }
}

extension EnvironmentValues {
    var openWikiURL: OpenWikiURLAction {
        get { self[OpenWikiURLKey.self] }
        set { self[OpenWikiURLKey.self] = newValue }
    }
}
