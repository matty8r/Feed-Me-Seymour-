//
//  FeedMeSeymourApp.swift
//  Feed Me, Seymour!
//
//  A native reader for macOS and iOS. One target, one codebase, two first-class
//  apps.
//

import SwiftUI
import SwiftData

@main
struct FeedMeSeymourApp: App {

    @State private var model: AppModel
    private let container: ModelContainer

    init() {
        let store = Persistence.makeStore()
        container = store.container
        _model = State(initialValue: AppModel(isCloudBacked: store.isCloudBacked))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .modelContainer(container)
        }
        .commands { FeedMeCommands(model: model) }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .environment(model.settings)
                .modelContainer(container)
        }
        #endif
    }
}
