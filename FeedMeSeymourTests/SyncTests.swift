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
        state.starUpdatedAt = .now
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

// MARK: - Read state versus favourites

/// Reading an article is common; starring one is rare and deliberate. When the
/// two share a clock and the record merges whole, the common event overwrites
/// the deliberate one — which is the difference between "favourites sync" and
/// "favourites sync until you read something".
@MainActor
@Suite("Favorites survive reading")
struct FavoriteClockTests {

    private func makeContext() -> ModelContext {
        ModelContext(Persistence.makeInMemoryContainer())
    }

    private func makeCoordinator() -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: "fav.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(isCloudBacked: true, defaults: defaults)
        coordinator.isEnabled = true
        return coordinator
    }

    /// Another device stars an article. This device then reads it. The star
    /// must survive: neither device disagrees about it, and one of them never
    /// said anything about it at all.
    @Test("Reading here does not unstar what another device starred")
    func readingDoesNotClobberARemoteStar() {
        let context = makeContext()
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Gazette")
        context.insert(feed)

        let article = Article(guid: "item-1", title: "Somewhere That's Green", publishedAt: .now)
        context.insert(article)
        article.feed = feed

        // Another device starred it a minute ago.
        let starred = SyncedArticleState(
            feedURLString: "https://example.com/feed",
            guid: "item-1"
        )
        starred.isStarred = true
        starred.starredAt = Date().addingTimeInterval(-60)
        starred.updatedAt = Date().addingTimeInterval(-60)
        starred.starUpdatedAt = Date().addingTimeInterval(-60)
        starred.title = "Somewhere That's Green"
        context.insert(starred)

        // Then this device reads it — later, so its clock is newer.
        article.setRead(true)

        makeCoordinator().reconcile(in: context)

        #expect(article.isRead)
        #expect(article.isStarred, "reading an article must not clear a favourite made elsewhere")

        let mirror = ((try? context.fetch(FetchDescriptor<SyncedArticleState>())) ?? []).first
        #expect(mirror?.isStarred == true, "and the mirror must not carry the loss back to the other device")
    }

    /// The mirror image: starred here, read there.
    @Test("Reading elsewhere does not unstar what this device starred")
    func remoteReadDoesNotClobberALocalStar() {
        let context = makeContext()
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Gazette")
        context.insert(feed)

        let article = Article(guid: "item-2", title: "Suddenly Seymour", publishedAt: .now)
        context.insert(article)
        article.feed = feed
        article.toggleStar()                    // starred here, a moment ago

        // Another device read it just now — newer clock, and it knows nothing
        // about the star.
        let read = SyncedArticleState(feedURLString: "https://example.com/feed", guid: "item-2")
        read.isRead = true
        read.isStarred = false
        read.updatedAt = Date().addingTimeInterval(60)
        context.insert(read)

        makeCoordinator().reconcile(in: context)

        #expect(article.isRead)
        #expect(article.isStarred, "a favourite must not be lost because another device read the article")
    }

    /// Unstarring is still a real action and must win when it is the newer one.
    @Test("Deliberately unstarring still propagates")
    func unstarringWins() {
        let context = makeContext()
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Gazette")
        context.insert(feed)

        let article = Article(guid: "item-3", title: "Feed Me", publishedAt: .now)
        context.insert(article)
        article.feed = feed
        article.isStarred = true
        article.starredAt = Date().addingTimeInterval(-120)
        article.stateUpdatedAt = Date().addingTimeInterval(-120)
        article.starUpdatedAt = Date().addingTimeInterval(-120)

        // Another device unstarred it since.
        let unstarred = SyncedArticleState(feedURLString: "https://example.com/feed", guid: "item-3")
        unstarred.isStarred = false
        unstarred.starredAt = nil
        unstarred.updatedAt = Date()
        unstarred.starUpdatedAt = Date()
        context.insert(unstarred)

        makeCoordinator().reconcile(in: context)

        #expect(!article.isStarred, "an explicit unstar is a decision and must survive")
    }
}

/// The reconcile pass answers `NSPersistentStoreRemoteChange`, and its own
/// save posts one of those. So a pass that finds nothing to do must not save —
/// otherwise it wakes itself, forever. That is not a hypothetical: it held a
/// core at 100% with the app sitting idle, because every save invalidated the
/// store and redrew every row in the timeline.
///
/// Checking `context.hasChanges` after a pass proves nothing, since the pass
/// saves what it wrote. What has to be counted is the save itself.
@MainActor
@Suite("Reconcile settles")
struct ReconcileIdempotenceTests {

    private func makeContext() -> ModelContext {
        ModelContext(Persistence.makeInMemoryContainer())
    }

    private func makeCoordinator() -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: "settle.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(isCloudBacked: true, defaults: defaults)
        coordinator.isEnabled = true
        return coordinator
    }

    /// How many times anything saved while `work` ran.
    private func countingSaves(_ work: () -> Void) -> Int {
        let counter = SaveCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: nil,
            queue: nil
        ) { _ in counter.bump() }
        defer { NotificationCenter.default.removeObserver(token) }
        work()
        return counter.value
    }

    private final class SaveCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    private func populate(_ context: ModelContext) {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Gazette")
        context.insert(feed)

        for index in 0..<8 {
            let article = Article(
                guid: "item-\(index)",
                title: "Feed Me \(index)",
                url: URL(string: "https://example.com/\(index)"),
                publishedAt: Date().addingTimeInterval(-Double(index) * 60)
            )
            context.insert(article)
            article.feed = feed
            // A mix of touched and untouched, so both the insert path and the
            // merge path are exercised.
            if index % 2 == 0 { article.setRead(true) }
            if index % 4 == 0 { article.toggleStar() }
        }
        try? context.save()
    }

    @Test("A second pass over unchanged data does not save")
    func secondPassDoesNotSave() {
        let context = makeContext()
        populate(context)
        let coordinator = makeCoordinator()

        let first = countingSaves { coordinator.reconcile(in: context) }
        #expect(first > 0, "the first pass has mirrors to write")

        let second = countingSaves { coordinator.reconcile(in: context) }
        #expect(second == 0, "a settled store must not be written again")
    }

    /// The specific shape that caused it: an article nobody ever starred, so
    /// both star clocks sit at `.distantPast` and every `>=` comparison
    /// between them is true.
    @Test("An unstarred article does not rewrite its mirror on every pass")
    func unstarredArticleSettles() {
        let context = makeContext()
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Gazette")
        context.insert(feed)

        let article = Article(guid: "item-1", title: "Suddenly Seymour", publishedAt: .now)
        context.insert(article)
        article.feed = feed
        article.setRead(true)
        try? context.save()

        let coordinator = makeCoordinator()
        coordinator.reconcile(in: context)
        #expect(article.starUpdatedAt == .distantPast)

        let second = countingSaves { coordinator.reconcile(in: context) }
        #expect(second == 0)
    }

    @Test("Real news still gets through after the store has settled")
    func stillAdoptsRemoteChanges() {
        let context = makeContext()
        populate(context)
        let coordinator = makeCoordinator()

        coordinator.reconcile(in: context)
        #expect(countingSaves { coordinator.reconcile(in: context) } == 0)

        // Another device stars something this one has not.
        let state = SyncedArticleState(feedURLString: "https://example.com/feed", guid: "item-3")
        state.isStarred = true
        state.starredAt = .now
        state.starUpdatedAt = .now
        state.updatedAt = .now
        state.title = "Feed Me 3"
        context.insert(state)
        try? context.save()

        coordinator.reconcile(in: context)

        let adopted = (try? context.fetch(FetchDescriptor<Article>()))?.first { $0.guid == "item-3" }
        #expect(adopted?.isStarred == true)
    }
}
