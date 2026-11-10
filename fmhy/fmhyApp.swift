//
//  fmhyApp.swift
//  fmhy
//

import SwiftUI
import SwiftData

@main
struct FMHYApp: App {
    @State private var store = WikiStore()

    private let modelContainer: ModelContainer = {
        let schema = Schema([Bookmark.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Check for Wiki Updates") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
