//
//  AppModel.swift
//  Feed Me, Seymour!
//
//  Everything the chrome needs to know: which tab, which feed, which article,
//  and whether the reader has taken over the pane.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case subscriptions, favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptions: "Feeds"
        case .favorites: "Favorites"
        }
    }

    var symbolName: String {
        switch self {
        case .subscriptions: "dot.radiowaves.up.forward"
        case .favorites: "star"
        }
    }
}

enum FeedSelection: Hashable {
    case all
    case unread
    case starred
    case feed(PersistentIdentifier)

    var isStarred: Bool { self == .starred }
}

@MainActor
@Observable
final class AppModel {

    // Chrome
    var sidebarTab: SidebarTab = .subscriptions
    /// Optional so that iPhone starts on the sidebar instead of pushing a list
    /// the reader never asked for.
    var selection: FeedSelection? = Platform.isPhone ? nil : .all
    var columnVisibility: NavigationSplitViewVisibility = .all

    // Timeline
    var selectedArticleID: PersistentIdentifier?
    var expandedArticleID: PersistentIdentifier?
    var searchText: String = ""

    /// The timeline publishes what it is actually showing so that menu commands
    /// and the keyboard can move through the same order the reader sees.
    var visibleArticleIDs: [PersistentIdentifier] = []

    // Sheets
    var isShowingAddSubscription = false
    var isShowingSettings = false
    var isShowingOPMLImporter = false
    var isShowingOPMLExporter = false
    var feedPendingDeletion: Feed?

    /// Transient banner text, used for "Subscribed to …" and refresh failures.
    var statusMessage: String?

    let settings = ReaderSettings()
    let refresher = FeedRefreshService()

    var isReaderExpanded: Bool { expandedArticleID != nil }

    // MARK: - Reading

    func open(_ article: Article, markRead: Bool = true) {
        selectedArticleID = article.persistentModelID
        expandedArticleID = article.persistentModelID
        if markRead, settings.marksReadOnOpen { article.isRead = true }
    }

    func toggleExpansion(for article: Article?) {
        guard let article else { return }
        if expandedArticleID == article.persistentModelID {
            collapse()
        } else {
            open(article)
        }
    }

    func collapse() {
        expandedArticleID = nil
    }

    // MARK: - Moving through the timeline

    private var selectedIndex: Int? {
        guard let selectedArticleID else { return nil }
        return visibleArticleIDs.firstIndex(of: selectedArticleID)
    }

    var canGoToNext: Bool {
        guard let index = selectedIndex else { return !visibleArticleIDs.isEmpty }
        return index + 1 < visibleArticleIDs.count
    }

    var canGoToPrevious: Bool {
        guard let index = selectedIndex else { return false }
        return index > 0
    }

    @discardableResult
    func goToNext() -> PersistentIdentifier? {
        let next: PersistentIdentifier?
        if let index = selectedIndex {
            next = index + 1 < visibleArticleIDs.count ? visibleArticleIDs[index + 1] : nil
        } else {
            next = visibleArticleIDs.first
        }
        guard let next else { return nil }
        selectedArticleID = next
        if isReaderExpanded { expandedArticleID = next }
        return next
    }

    @discardableResult
    func goToPrevious() -> PersistentIdentifier? {
        guard let index = selectedIndex, index > 0 else { return nil }
        let previous = visibleArticleIDs[index - 1]
        selectedArticleID = previous
        if isReaderExpanded { expandedArticleID = previous }
        return previous
    }

    // MARK: - Selection helpers

    func select(_ selection: FeedSelection?) {
        self.selection = selection
        expandedArticleID = nil
        selectedArticleID = nil
    }

    func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if statusMessage == message { statusMessage = nil }
        }
    }
}

// MARK: - Fetching by identifier

extension ModelContext {
    /// SwiftUI selections are identifiers; the views need the object back.
    func article(with id: PersistentIdentifier?) -> Article? {
        guard let id else { return nil }
        return registeredModel(for: id) ?? model(for: id) as? Article
    }

    func feed(with id: PersistentIdentifier?) -> Feed? {
        guard let id else { return nil }
        return registeredModel(for: id) ?? model(for: id) as? Feed
    }
}
