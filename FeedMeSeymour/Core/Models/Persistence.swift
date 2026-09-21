//
//  Persistence.swift
//  Feed Me, Seymour!
//

import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Feed.self, Article.self, MediaAttachment.self])

    /// The on-disk store used by the shipping app.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration("FeedMeSeymour", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A store we cannot open is worse than no store: fall back to memory so
            // the app still launches and the reader can re-import their OPML.
            assertionFailure("Falling back to an in-memory store: \(error)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration("FeedMeSeymour-Fallback", schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    /// Previews and tests.
    static func makeInMemoryContainer() -> ModelContainer {
        try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
        for (index, entry) in starterFeeds.enumerated() {
            guard let url = URL(string: entry.url) else { continue }
            context.insert(Feed(feedURL: url, title: entry.title, sortIndex: index))
        }
        try? context.save()
    }
}
