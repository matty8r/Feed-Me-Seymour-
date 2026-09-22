//
//  SyncTests.swift
//  Feed Me, Seymour! Tests
//
//  The reconcile pass, exercised against an in-memory store. No CloudKit is
//  involved: the mirror records are ordinary models, and "what another device
//  did" is simply a mirror row written by hand.
//

import Testing
import Foundation
import SwiftData
@testable import FeedMeSeymour

@MainActor
@Suite("iCloud reconcile")
struct SyncTests {

    private func makeContext() -> ModelContext {
        ModelContext(Persistence.makeInMemoryContainer())
    }

    private func makeCoordinator(enabled: Bool = true, cloudBacked: Bool = true) -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: "sync.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(isCloudBacked: cloudBacked, defaults: defaults)
        coordinator.isEnabled = enabled
        return coordinator
    }

    private func insertFeed(_ context: ModelContext, url: String = "https://example.com/feed", title: String = "Skid Row Gazette") -> Feed {
        let feed = Feed(feedURL: URL(string: url)!, title: title)
        context.insert(feed)
        return feed
    }

    private func mirrors(_ context: ModelContext) -> [SyncedSubscription] {
        (try? context.fetch(FetchDescriptor<SyncedSubscription>())) ?? []
    }

    private func states(_ context: ModelContext) -> [SyncedArticleState] {
        (try? context.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
    }

    private func feeds(_ context: ModelContext) -> [Feed] {
        (try? context.fetch(FetchDescriptor<Feed>())) ?? []
    }

    private func articles(_ context: ModelContext) -> [Article] {
        (try? context.fetch(FetchDescriptor<Article>())) ?? []
    }

    // MARK: - Subscriptions

    @Test("A local subscription gets mirrored")
    func pushesSubscription() {
        let context = makeContext()
        let feed = insertFeed(context)

        makeCoordinator().reconcile(in: context)

        let mirrored = mirrors(context)
        #expect(mirrored.count == 1)
        #expect(mirrored.first?.feedURLString == feed.feedURL.absoluteString)
        #expect(mirrored.first?.removedAt == nil)
    }

    @Test("A subscription from another device is adopted and reported for fetching")
    func adoptsSubscription() {
        let context = makeContext()
        let mirror = SyncedSubscription(feedURLString: "https://example.com/atom", title: "Mushnik's")
        mirror.sortIndex = 4
        mirror.customTitle = "The Flower Shop"
        context.insert(mirror)

        let adopted = makeCoordinator().reconcile(in: context)

        #expect(adopted.count == 1)
        let local = feeds(context)
        #expect(local.count == 1)
        #expect(local.first?.feedURL.absoluteString == "https://example.com/atom")
        #expect(local.first?.customTitle == "The Flower Shop")
        #expect(local.first?.sortIndex == 4)
    }

    @Test("A tombstone removes the local subscription")
    func honoursTombstone() {
        let context = makeContext()
        let feed = insertFeed(context)
        feed.dateAdded = .now.addingTimeInterval(-3600)

        let mirror = SyncedSubscription.mirroring(feed)
        mirror.removedAt = .now
        context.insert(mirror)

        makeCoordinator().reconcile(in: context)

        #expect(feeds(context).isEmpty)
    }

    @Test("Re-subscribing after a removal wins over the tombstone")
    func resubscribeBeatsTombstone() {
        let context = makeContext()
        let feed = insertFeed(context)
        feed.dateAdded = .now

        let mirror = SyncedSubscription(feedURLString: feed.feedURL.absoluteString, title: feed.title)
        mirror.removedAt = .now.addingTimeInterval(-3600)
        context.insert(mirror)

        makeCoordinator().reconcile(in: context)

        #expect(feeds(context).count == 1)
        #expect(mirrors(context).first?.removedAt == nil)
    }

    @Test("A newer rename on another device is adopted")
    func adoptsRename() {
        let context = makeContext()
        let feed = insertFeed(context)
        feed.metadataUpdatedAt = .now.addingTimeInterval(-600)

        let mirror = SyncedSubscription(feedURLString: feed.feedURL.absoluteString, title: feed.title)
        mirror.customTitle = "Renamed Elsewhere"
        mirror.updatedAt = .now
        context.insert(mirror)

        makeCoordinator().reconcile(in: context)

        #expect(feed.customTitle == "Renamed Elsewhere")
    }

    @Test("A newer local rename is pushed instead")
    func pushesRename() {
        let context = makeContext()
        let feed = insertFeed(context)
        let mirror = SyncedSubscription(feedURLString: feed.feedURL.absoluteString, title: feed.title)
        mirror.customTitle = "Stale"
        mirror.updatedAt = .now.addingTimeInterval(-600)
        context.insert(mirror)

        feed.customTitle = "Renamed Here"
        feed.touchMetadata()

        makeCoordinator().reconcile(in: context)

        #expect(mirrors(context).first?.customTitle == "Renamed Here")
    }

    @Test("Duplicate mirrors for one feed collapse to the newest")
    func collapsesDuplicateMirrors() {
        let context = makeContext()
        _ = insertFeed(context)

        let older = SyncedSubscription(feedURLString: "https://example.com/feed", title: "Older")
        older.updatedAt = .now.addingTimeInterval(-600)
        let newer = SyncedSubscription(feedURLString: "https://example.com/feed", title: "Newer")
        newer.updatedAt = .now
        context.insert(older)
        context.insert(newer)

        makeCoordinator().reconcile(in: context)

        #expect(mirrors(context).count == 1)
    }

    // MARK: - Read and favourite state

    @Test("Only articles the reader touched get a state record")
    func mirrorsTouchedArticlesOnly() {
        let context = makeContext()
        let feed = insertFeed(context)

        let untouched = Article(guid: "a", title: "Untouched", publishedAt: .now)
        let starred = Article(guid: "b", title: "Starred", publishedAt: .now)
        context.insert(untouched)
        context.insert(starred)
        untouched.feed = feed
        starred.feed = feed
        starred.toggleStar()

        makeCoordinator().reconcile(in: context)

        let recorded = states(context)
        #expect(recorded.count == 1)
        #expect(recorded.first?.guid == "b")
        #expect(recorded.first?.isStarred == true)
    }

    @Test("A newer remote state wins over the local one")
    func adoptsRemoteState() {
        let context = makeContext()
        let feed = insertFeed(context)
        let article = Article(guid: "a", title: "Somewhere That's Green", publishedAt: .now)
        context.insert(article)
        article.feed = feed
        article.setRead(false)
        article.stateUpdatedAt = .now.addingTimeInterval(-600)

        let state = SyncedArticleState(feedURLString: feed.feedURL.absoluteString, guid: "a")
        state.isRead = true
        state.isStarred = true
        state.starredAt = .now
        state.updatedAt = .now
        context.insert(state)

        makeCoordinator().reconcile(in: context)

        #expect(article.isRead)
        #expect(article.isStarred)
    }

    @Test("A newer local state is pushed instead")
    func pushesLocalState() {
        let context = makeContext()
        let feed = insertFeed(context)
        let article = Article(guid: "a", title: "Feed Me", publishedAt: .now)
        context.insert(article)
        article.feed = feed

        let state = SyncedArticleState(feedURLString: feed.feedURL.absoluteString, guid: "a")
        state.updatedAt = .now.addingTimeInterval(-600)
        context.insert(state)

        article.setRead(true)

        makeCoordinator().reconcile(in: context)

        #expect(states(context).first?.isRead == true)
    }

    @Test("A favourite whose body never arrived becomes a placeholder")
    func materializesMissingFavorite() {
        let context = makeContext()
        let feed = insertFeed(context)

        let state = SyncedArticleState(feedURLString: feed.feedURL.absoluteString, guid: "ghost")
        state.isStarred = true
        state.starredAt = .now
        state.updatedAt = .now
        state.title = "Suddenly Seymour"
        state.articleURLString = "https://example.com/suddenly"
        state.publishedAt = .now.addingTimeInterval(-86_400)
        context.insert(state)

        makeCoordinator().reconcile(in: context)

        let created = articles(context)
        #expect(created.count == 1)
        #expect(created.first?.guid == "ghost")
        #expect(created.first?.title == "Suddenly Seymour")
        #expect(created.first?.isStarred == true)
        #expect(created.first?.isPlaceholder == true)
        #expect(created.first?.feed?.feedURL == feed.feedURL)
    }

    @Test("Read state nobody has touched in months is dropped; favorites are kept")
    func prunesStaleStates() {
        let context = makeContext()
        let feed = insertFeed(context)

        let stale = SyncedArticleState(feedURLString: feed.feedURL.absoluteString, guid: "old")
        stale.isRead = true
        stale.updatedAt = .now.addingTimeInterval(-SyncCoordinator.stateRetention - 86_400)

        let oldFavorite = SyncedArticleState(feedURLString: feed.feedURL.absoluteString, guid: "keeper")
        oldFavorite.isStarred = true
        oldFavorite.updatedAt = .now.addingTimeInterval(-SyncCoordinator.stateRetention * 4)

        context.insert(stale)
        context.insert(oldFavorite)

        makeCoordinator().reconcile(in: context)

        let remaining = states(context).map(\.guid)
        #expect(!remaining.contains("old"))
        #expect(remaining.contains("keeper"))
    }

    // MARK: - Off

    @Test("Nothing is written when sync is off")
    func respectsTheToggle() {
        let context = makeContext()
        _ = insertFeed(context)

        makeCoordinator(enabled: false).reconcile(in: context)
        #expect(mirrors(context).isEmpty)

        makeCoordinator(cloudBacked: false).reconcile(in: context)
        #expect(mirrors(context).isEmpty)
    }

    @Test("Unsubscribing leaves a tombstone rather than a hole")
    func unsubscribeWritesTombstone() {
        let context = makeContext()
        let feed = insertFeed(context)
        let coordinator = makeCoordinator()
        coordinator.reconcile(in: context)

        coordinator.noteUnsubscribe(from: feed, in: context)
        context.delete(feed)
        try? context.save()

        #expect(feeds(context).isEmpty)
        #expect(mirrors(context).count == 1)
        #expect(mirrors(context).first?.removedAt != nil)

        // A second pass must not resurrect it.
        coordinator.reconcile(in: context)
        #expect(feeds(context).isEmpty)
    }
}
