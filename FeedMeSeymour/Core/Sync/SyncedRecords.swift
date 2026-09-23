//
//  SyncedRecords.swift
//  Feed Me, Seymour!
//
//  The only things that travel through iCloud. Article bodies stay on the
//  device that downloaded them — they are re-fetchable from the publisher in
//  seconds, and pushing a few thousand HTML blobs through the private database
//  would be slow, expensive and pointless.
//
//  These records live in their own CloudKit-backed store, so they must obey
//  CloudKit's schema rules: every property optional or defaulted, no unique
//  constraints, and no relationships (models in a synced store cannot relate to
//  models in a local one).
//
//  They are keyed by *natural* identifiers — the feed's URL, and the item's
//  guid within that feed — because `PersistentIdentifier` and our own `uuid`
//  differ on every device.
//

import Foundation
import SwiftData

@Model
final class SyncedSubscription {

    var feedURLString: String = ""
    var title: String = ""
    var customTitle: String?
    var homePageURLString: String?
    var sortIndex: Int = 0
    var dateAdded: Date = Date()

    /// Last-writer-wins clock for the editable metadata above.
    var updatedAt: Date = Date()

    /// A tombstone. Hard-deleting the record would simply let the next device
    /// to sync re-create the subscription from its own copy.
    var removedAt: Date?

    init(feedURLString: String, title: String) {
        self.feedURLString = feedURLString
        self.title = title
    }

    /// A factory rather than a convenience initializer: `@Model` rewrites
    /// initializers, and delegating between them is not worth the surprise.
    static func mirroring(_ feed: Feed) -> SyncedSubscription {
        let mirror = SyncedSubscription(feedURLString: feed.feedURL.absoluteString, title: feed.title)
        mirror.apply(from: feed)
        return mirror
    }

    func apply(from feed: Feed) {
        title = feed.title
        customTitle = feed.customTitle
        homePageURLString = feed.homePageURL?.absoluteString
        sortIndex = feed.sortIndex
        dateAdded = feed.dateAdded
        updatedAt = feed.metadataUpdatedAt
        removedAt = nil
    }

    var homePageURL: URL? {
        homePageURLString.flatMap(URL.init(string:))
    }
}

@Model
final class SyncedArticleState {

    /// `feedURL\nguid`. Stored rather than computed so it can be used in a fetch.
    var stateKey: String = ""

    var feedURLString: String = ""
    var guid: String = ""

    var isRead: Bool = false
    var isStarred: Bool = false
    var starredAt: Date?

    /// Clock for `isRead`.
    var updatedAt: Date = Date()

    /// Clock for `isStarred`, kept apart from the read clock so that reading an
    /// article on one device cannot undo a favourite made on another.
    var starUpdatedAt: Date = Date.distantPast

    /// Just enough to show a favourite whose body this device has never seen.
    /// A stub article is built from these three fields and filled in properly
    /// the next time the feed is refreshed.
    var title: String = ""
    var articleURLString: String?
    var publishedAt: Date = Date.distantPast

    init(feedURLString: String, guid: String) {
        self.feedURLString = feedURLString
        self.guid = guid
        self.stateKey = Self.key(feedURLString: feedURLString, guid: guid)
    }

    static func mirroring(_ article: Article, feedURLString: String) -> SyncedArticleState {
        let state = SyncedArticleState(feedURLString: feedURLString, guid: article.guid)
        state.apply(from: article)
        return state
    }

    static func key(feedURLString: String, guid: String) -> String {
        "\(feedURLString)\n\(guid)"
    }

    func apply(from article: Article) {
        isRead = article.isRead
        isStarred = article.isStarred
        starredAt = article.starredAt
        updatedAt = article.stateUpdatedAt
        starUpdatedAt = article.starUpdatedAt
        title = article.title
        articleURLString = article.url?.absoluteString
        publishedAt = article.publishedAt
    }

    var articleURL: URL? {
        articleURLString.flatMap(URL.init(string:))
    }

    /// Read state for something nobody has looked at in months is not worth a
    /// CloudKit record. Favourites are kept forever.
    func isStale(asOf now: Date, retention: TimeInterval) -> Bool {
        !isStarred && now.timeIntervalSince(updatedAt) > retention
    }
}
