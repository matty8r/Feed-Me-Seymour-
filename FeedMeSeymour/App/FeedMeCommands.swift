//
//  FeedMeCommands.swift
//  Feed Me, Seymour!
//
//  Menu bar on macOS, ⌘-HUD shortcuts on iPad. Every shortcut here carries a
//  modifier so nothing steals a keystroke from the search field; bare Space and
//  Escape are handled by the views that own focus.
//

import SwiftUI
import SwiftData

struct FeedMeCommands: Commands {

    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Subscription…") { model.isShowingAddSubscription = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Subscriptions…") { model.isShowingOPMLImporter = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Subscriptions…") { model.isShowingOPMLExporter = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Article") {
            Button(model.isReaderExpanded ? "Close Article" : "Read Article") {
                NotificationCenter.default.post(name: .toggleReader, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Next Article") { model.goToNext() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!model.canGoToNext)

            Button("Previous Article") { model.goToPrevious() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!model.canGoToPrevious)

            Divider()

            Button("Toggle Favorite") {
                NotificationCenter.default.post(name: .toggleFavorite, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Toggle Read") {
                NotificationCenter.default.post(name: .toggleRead, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Open in Browser") {
                NotificationCenter.default.post(name: .openInBrowser, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("Subscriptions") {
            Button("Refresh All") {
                NotificationCenter.default.post(name: .refreshAll, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.refresher.isRefreshing)

            Button("Mark All as Read") {
                NotificationCenter.default.post(name: .markAllRead, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { model.settings.nudgeSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!model.settings.canGrow)

            Button("Smaller Text") { model.settings.nudgeSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!model.settings.canShrink)

            Button("Actual Size") { model.settings.resetTypography() }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Picker("Reading Theme", selection: Binding(
                get: { model.settings.theme },
                set: { model.settings.theme = $0 }
            )) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        }
    }
}

// MARK: - Menu → view messages

extension Notification.Name {
    static let toggleReader = Notification.Name("FeedMe.toggleReader")
    static let toggleFavorite = Notification.Name("FeedMe.toggleFavorite")
    static let toggleRead = Notification.Name("FeedMe.toggleRead")
    static let openInBrowser = Notification.Name("FeedMe.openInBrowser")
    static let refreshAll = Notification.Name("FeedMe.refreshAll")
    static let markAllRead = Notification.Name("FeedMe.markAllRead")
}
