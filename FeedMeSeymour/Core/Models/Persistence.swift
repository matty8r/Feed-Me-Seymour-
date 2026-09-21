//
//  Persistence.swift
//  Feed Me, Seymour!
//

import Foundation
import SwiftData

enum Persistence {

    /// Article bodies, their media and the feeds they belong to. Never leaves
    /// the device: every byte here is re-fetchable from the publisher.
    static let localModels: [any PersistentModel.Type] = [Feed.self, Article.self, MediaAttachment.self]

    /// The small mirror records that travel through the private CloudKit
    /// database. See `SyncedRecords.swift` for why they are separate.
    static let cloudModels: [any PersistentModel.Type] = [SyncedSubscription.self, SyncedArticleState.self]

    static let schema = Schema(localModels + cloudModels)

    struct Store {
        var container: ModelContainer
        /// False when the CloudKit-backed configuration could not be opened —
        /// no entitlement, no signed-in account, or no container provisioned.
        var isCloudBacked: Bool
    }

    /// Two configurations in one container. Fetches are routed by model type,
    /// so callers never need to know which store a model lives in.
    static func makeStore() -> Store {
        let local = ModelConfiguration(
            "FeedMeSeymourLocal",
            schema: Schema(localModels),
            cloudKitDatabase: .none
        )

        let cloud = ModelConfiguration(
            "FeedMeSeymourCloud",
            schema: Schema(cloudModels),
            cloudKitDatabase: .automatic
        )

        if let container = try? ModelContainer(for: schema, configurations: local, cloud) {
            return Store(container: container, isCloudBacked: true)
        }

        // Building without a paid team, signed out of iCloud, or running where
        // the container isn't provisioned: keep everything, just locally.
        let offline = ModelConfiguration(
            "FeedMeSeymourCloud",
            schema: Schema(cloudModels),
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: local, offline) {
            return Store(container: container, isCloudBacked: false)
        }

        // A store we cannot open at all is worse than no store: fall back to
        // memory so the app still launches and the reader can re-import OPML.
        assertionFailure("Falling back to an in-memory store")
        let memory = try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return Store(container: memory, isCloudBacked: false)
    }

    /// Previews and tests. Local only, so nothing touches a real iCloud account.
    static func makeInMemoryContainer() -> ModelContainer {
        try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}

// MARK: - Starter subscriptions

extension Persistence {
    struct StarterFeed: Identifiable, Hashable, Sendable {
        var title: String
        var url: String
        var id: String { url }
    }

    /// A handful of well-typeset, media-rich feeds so a fresh install is not an empty room.
    static let starterFeeds: [StarterFeed] = [
        StarterFeed(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main"),
        StarterFeed(title: "NASA Image of the Day", url: "https://www.nasa.gov/rss/dyn/lg_image_of_the_day.rss"),
        StarterFeed(title: "The Verge", url: "https://www.theverge.com/rss/index.xml"),
        StarterFeed(title: "Kottke", url: "https://feeds.kottke.org/main"),
        StarterFeed(title: "NPR News", url: "https://feeds.npr.org/1001/rss.xml")
    ]

    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Feed>())) ?? 0
        guard existing == 0 else { return }

        // A second device shouldn't get the starter set on top of the
        // subscriptions iCloud is about to hand it.
        let mirrored = (try? context.fetchCount(FetchDescriptor<SyncedSubscription>())) ?? 0
        guard mirrored == 0 else { return }
        for (index, entry) in starterFeeds.enumerated() {
            guard let url = URL(string: entry.url) else { continue }
            context.insert(Feed(feedURL: url, title: entry.title, sortIndex: index))
        }
        try? context.save()
    }
}
