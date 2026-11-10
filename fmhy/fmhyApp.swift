//
//  fmhyApp.swift
//  fmhy
//

import SwiftUI
import SwiftData

@main
struct FMHYApp: App {
    @State private var store = WikiStore()
    @State private var postsStore = FMHYPostsStore()

    private let modelContainer: ModelContainer = {
        let schema = Schema([Bookmark.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        // A damaged store should not take the app down: start empty and let the
        // opt-in backup refill the list instead of crashing on launch.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(postsStore)
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
