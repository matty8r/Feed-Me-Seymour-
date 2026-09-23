//
//  SyncCoordinator.swift
//  Feed Me, Seymour!
//
//  Keeps the local store and the iCloud mirror store in agreement.
//
//  SwiftData will not let a model in a CloudKit-backed store hold a
//  relationship to a model in a local one, so `Feed`/`Article` keep their
//  relationship and their own store, and small mirror records carry the
//  syncable facts across. Everything is matched on natural keys — a feed's URL,
//  an item's guid — because identifiers differ on every device.
//
//  Conflicts are resolved last-writer-wins on explicit clocks
//  (`Feed.metadataUpdatedAt`, `Article.stateUpdatedAt`) rather than on whatever
//  order CloudKit happens to deliver changes in.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SyncCoordinator {

    /// Read state older than this is dropped from iCloud. Favourites are kept
    /// forever; whether you read something two months ago is not worth a record.
    static let stateRetention: TimeInterval = 60 * 24 * 60 * 60

    private static let enabledKey = "sync.enabled"

    /// Whether the container actually came up with a CloudKit-backed store.
    let isCloudBacked: Bool

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    private(set) var isSyncing = false
    /// When the app last ran its own pass. Deliberately not what the status
    /// line leads with: the pass can finish cleanly while CloudKit rejects
    /// every record it produced.
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    /// What CloudKit itself reports. This is what the status line believes.
    let activity = CloudKitActivity()

    private let defaults: UserDefaults

    init(isCloudBacked: Bool, defaults: UserDefaults = .standard) {
        self.isCloudBacked = isCloudBacked
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var isActive: Bool { isCloudBacked && isEnabled }

    var statusDescription: String {
        if !isCloudBacked { return "iCloud isn’t available on this device." }
        if !isEnabled { return "Off. Subscriptions and favorites stay on this device." }
        if isSyncing { return "Syncing…" }
        if let lastError { return lastError }
        // CloudKit's own account of itself comes first. Only when it has
        // nothing to say do we fall back to "we ran a pass".
        if let summary = activity.summary { return summary }
        if let lastSyncDate { return "Checked \(lastSyncDate.relativeStamp)." }
        return "On."
    }

    /// True when iCloud has stopped for this launch and only reopening the app
    /// will start it again.
    var needsRelaunch: Bool { isActive && activity.needsRelaunch }

    /// True when the most recent thing CloudKit did was fail.
    var isFailing: Bool {
        guard isActive, let failure = activity.lastFailure else { return false }
        return failure.endedAt > (activity.lastSuccess?.endedAt ?? .distantPast)
    }

    // MARK: - The pass

    /// Pulls anything new out of the mirror store and pushes anything this
    /// device knows better. Returns subscriptions adopted from another device,
    /// which the caller should fetch for the first time.
    @discardableResult
    func reconcile(in context: ModelContext) -> [Feed] {
        guard isActive, !isSyncing else { return [] }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = .now
        }

        let now = Date.now
        var feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let adopted = reconcileSubscriptions(feeds: &feeds, context: context)
        reconcileArticleStates(feeds: feeds, context: context, now: now)
        pruneStates(context: context, now: now)

        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        return adopted
    }

    /// Records the intent to unsubscribe. A hard delete would be undone by the
    /// next device to sync, which still has the subscription.
    func noteUnsubscribe(from feed: Feed, in context: ModelContext) {
        guard isActive else { return }
        let key = feed.feedURL.absoluteString
        let descriptor = FetchDescriptor<SyncedSubscription>(
            predicate: #Predicate { $0.feedURLString == key }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            let mirror = SyncedSubscription(feedURLString: key, title: feed.title)
            mirror.removedAt = .now
            context.insert(mirror)
        } else {
            for mirror in existing { mirror.removedAt = .now }
        }
    }

    // MARK: - Subscriptions

    private func reconcileSubscriptions(feeds: inout [Feed], context: ModelContext) -> [Feed] {
        let mirrors = (try? context.fetch(FetchDescriptor<SyncedSubscription>())) ?? []
        let mirrorsByURL = deduplicate(mirrors, context: context)

        var surviving: [Feed] = []
        var seen = Set<String>()

        for feed in feeds {
            let key = feed.feedURL.absoluteString
            seen.insert(key)

            guard let mirror = mirrorsByURL[key] else {
                context.insert(SyncedSubscription.mirroring(feed))
                surviving.append(feed)
                continue
            }

            if let removedAt = mirror.removedAt {
                if removedAt >= feed.dateAdded {
                    // Unsubscribed on another device after this copy was added.
                    context.delete(feed)
                } else {
                    // Re-subscribed here since the removal; the newer intent wins.
                    mirror.apply(from: feed)
                    surviving.append(feed)
                }
                continue
            }

            if mirror.updatedAt > feed.metadataUpdatedAt {
                apply(mirror, to: feed)
            } else if feed.metadataUpdatedAt > mirror.updatedAt {
                mirror.apply(from: feed)
            }
            surviving.append(feed)
        }

        var adopted: [Feed] = []
        for mirror in mirrorsByURL.values where mirror.removedAt == nil && !seen.contains(mirror.feedURLString) {
            guard let url = URL(string: mirror.feedURLString) else { continue }
            let feed = Feed(
                feedURL: url,
                title: mirror.title,
                homePageURL: mirror.homePageURL,
                sortIndex: mirror.sortIndex
            )
            feed.customTitle = mirror.customTitle
            feed.dateAdded = mirror.dateAdded
            feed.metadataUpdatedAt = mirror.updatedAt
            context.insert(feed)
            adopted.append(feed)
        }

        feeds = surviving + adopted
        return adopted
    }

    /// The publisher's own title is refreshed on every fetch, so a stale mirror
    /// must not overwrite it. The reader's choices — a rename, the ordering —
    /// are exactly what should travel.
    private func apply(_ mirror: SyncedSubscription, to feed: Feed) {
        if feed.title.isEmpty { feed.title = mirror.title }
        if feed.homePageURL == nil { feed.homePageURL = mirror.homePageURL }
        feed.customTitle = mirror.customTitle
        feed.sortIndex = mirror.sortIndex
        feed.metadataUpdatedAt = mirror.updatedAt
    }

    // MARK: - Read and favourite state

    private func reconcileArticleStates(feeds: [Feed], context: ModelContext, now: Date) {
        let feedsByURL = Dictionary(
            feeds.map { ($0.feedURL.absoluteString, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let states = (try? context.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
        let statesByKey = deduplicateStates(states, context: context)

        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        var matched = Set<String>()

        for article in articles {
            guard let feedURL = article.feed?.feedURL.absoluteString else { continue }
            let key = SyncedArticleState.key(feedURLString: feedURL, guid: article.guid)
            matched.insert(key)

            guard let state = statesByKey[key] else {
                // Only articles the reader has actually touched are worth a record.
                if article.isRead || article.isStarred {
                    context.insert(SyncedArticleState.mirroring(article, feedURLString: feedURL))
                }
                continue
            }

            if state.updatedAt > article.stateUpdatedAt {
                // Adopting a remote clock, so assign directly rather than
                // through `setRead`, which would stamp this device as newer.
                article.isRead = state.isRead
                article.isStarred = state.isStarred
                article.starredAt = state.starredAt
                article.stateUpdatedAt = state.updatedAt
            } else if article.stateUpdatedAt > state.updatedAt {
                state.apply(from: article)
            }
        }

        // A favourite starred on another device whose body has never reached
        // this one. Stand in a stub so it shows up in Favorites; the next
        // refresh of that feed matches it by guid and fills it in.
        for state in statesByKey.values where state.isStarred && !matched.contains(state.stateKey) {
            guard let feed = feedsByURL[state.feedURLString] else { continue }
            let stub = Article(
                guid: state.guid,
                title: state.title.nilIfEmpty ?? "Favorite",
                url: state.articleURL,
                publishedAt: state.publishedAt == .distantPast ? (state.starredAt ?? now) : state.publishedAt
            )
            stub.isStarred = true
            stub.isRead = state.isRead
            stub.starredAt = state.starredAt
            stub.stateUpdatedAt = state.updatedAt
            stub.isPlaceholder = true
            context.insert(stub)
            stub.feed = feed
        }
    }

    private func pruneStates(context: ModelContext, now: Date) {
        let states = (try? context.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
        for state in states where state.isStale(asOf: now, retention: Self.stateRetention) {
            context.delete(state)
        }
    }

    // MARK: - Duplicate mirrors

    /// Two devices can both create a mirror for the same feed before either has
    /// seen the other's. Keep the newest, carry over any tombstone, drop the rest.
    private func deduplicate(_ mirrors: [SyncedSubscription], context: ModelContext) -> [String: SyncedSubscription] {
        var winners: [String: SyncedSubscription] = [:]
        for mirror in mirrors {
            guard let existing = winners[mirror.feedURLString] else {
                winners[mirror.feedURLString] = mirror
                continue
            }
            let winner = mirror.updatedAt > existing.updatedAt ? mirror : existing
            let loser = winner === mirror ? existing : mirror
            if let removedAt = loser.removedAt, (winner.removedAt ?? .distantPast) < removedAt {
                winner.removedAt = removedAt
            }
            winners[mirror.feedURLString] = winner
            context.delete(loser)
        }
        return winners
    }

    private func deduplicateStates(_ states: [SyncedArticleState], context: ModelContext) -> [String: SyncedArticleState] {
        var winners: [String: SyncedArticleState] = [:]
        for state in states {
            guard let existing = winners[state.stateKey] else {
                winners[state.stateKey] = state
                continue
            }
            let winner = state.updatedAt > existing.updatedAt ? state : existing
            context.delete(winner === state ? existing : state)
            winners[state.stateKey] = winner
        }
        return winners
    }
}
