//
//  Feed.swift
//  Feed Me, Seymour!
//
//  A subscription. One row in the sidebar; many articles in the timeline.
//

import Foundation
import SwiftData

@Model
final class Feed {
    /// Stable identity that survives export/import, independent of the store's own row id.
    var uuid: UUID = UUID()

    /// The canonical address of the XML/JSON document we poll.
    var feedURL: URL = URL(string: "https://example.com/feed")!

    /// Publisher supplied title, overridable by the reader.
    var title: String = ""

    /// A title the reader typed in themselves. Wins over `title` when present.
    var customTitle: String?

    var feedDescription: String?
    var homePageURL: URL?
    var iconURL: URL?

    var dateAdded: Date = Date()
    var lastFetched: Date?
    var lastFetchErrorDescription: String?

    /// Conditional-GET bookkeeping so a refresh of an unchanged feed costs one 304.
    var httpETag: String?
    var httpLastModified: String?

    /// Manual ordering in the sidebar.
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []

    init(
        feedURL: URL,
        title: String,
        feedDescription: String? = nil,
        homePageURL: URL? = nil,
        iconURL: URL? = nil,
        sortIndex: Int = 0
    ) {
        self.uuid = UUID()
        self.feedURL = feedURL
        self.title = title
        self.feedDescription = feedDescription
        self.homePageURL = homePageURL
        self.iconURL = iconURL
        self.dateAdded = Date()
        self.sortIndex = sortIndex
    }

    /// What the UI should actually print.
    var displayTitle: String {
        if let customTitle, !customTitle.trimmed.isEmpty { return customTitle }
        if !title.trimmed.isEmpty { return title }
        return feedURL.host() ?? feedURL.absoluteString
    }

    var unreadCount: Int {
        articles.reduce(into: 0) { $0 += $1.isRead ? 0 : 1 }
    }

    /// A site favicon, used when the feed itself advertises no artwork.
    var fallbackIconURL: URL? {
        guard let host = (homePageURL ?? feedURL).host() else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    var effectiveIconURL: URL? { iconURL ?? fallbackIconURL }
}
