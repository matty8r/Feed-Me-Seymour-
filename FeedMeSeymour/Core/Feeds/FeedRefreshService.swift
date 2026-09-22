//
//  FeedRefreshService.swift
//  Feed Me, Seymour!
//
//  Fetch every subscription at once off the main actor, then merge the results
//  into SwiftData on it. Nothing here blocks the timeline.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class FeedRefreshService {

    /// Articles kept per feed before the oldest unstarred ones are pruned.
    static let retentionLimit = 300

    var isRefreshing = false
    var completedCount = 0
    var totalCount = 0
    var lastRefreshDate: Date?
    var lastErrorMessage: String?

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    // MARK: - Refreshing

    func refreshAll(in context: ModelContext) async {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        await refresh(feeds, in: context)
    }

    func refresh(_ feeds: [Feed], in context: ModelContext) async {
        guard !isRefreshing, !feeds.isEmpty else { return }

        isRefreshing = true
        completedCount = 0
        totalCount = feeds.count
        lastErrorMessage = nil
        defer {
            isRefreshing = false
            lastRefreshDate = .now
        }

        // Snapshot what the network layer needs; model objects stay on this actor.
        let requests = feeds.map { (id: $0.uuid, url: $0.feedURL, etag: $0.httpETag, modified: $0.httpLastModified) }
        let byID = Dictionary(feeds.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        let results = await withTaskGroup(of: (UUID, Result<FeedFetchOutcome, Error>).self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let outcome = try await FeedFetcher.shared.fetch(url: request.url, etag: request.etag, lastModified: request.modified)
                        return (request.id, .success(outcome))
                    } catch {
                        return (request.id, .failure(error))
                    }
                }
            }
            var collected: [(UUID, Result<FeedFetchOutcome, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var failures: [String] = []
        for (id, result) in results {
            completedCount += 1
            guard let feed = byID[id] else { continue }

            switch result {
            case .success(.notModified):
                feed.lastFetched = .now
                feed.lastFetchErrorDescription = nil

            case .success(.fetched(let fetched)):
                merge(fetched, into: feed, context: context)

            case .failure(let error):
                feed.lastFetched = .now
                feed.lastFetchErrorDescription = error.localizedDescription
                failures.append("\(feed.displayTitle): \(error.localizedDescription)")
            }
        }

        try? context.save()

        if failures.count == results.count, let first = failures.first {
            lastErrorMessage = first
        } else if !failures.isEmpty {
            lastErrorMessage = failures.count == 1
                ? failures[0]
                : "\(failures.count) subscriptions couldn’t be refreshed."
        }
    }

    func refresh(_ feed: Feed, in context: ModelContext) async {
        await refresh([feed], in: context)
    }

    // MARK: - Merging

    private func merge(_ fetched: FeedFetchResult, into feed: Feed, context: ModelContext) {
        let parsed = fetched.feed

        if let title = parsed.title?.nilIfEmpty { feed.title = title }
        if let subtitle = parsed.subtitle?.nilIfEmpty { feed.feedDescription = subtitle }
        if let home = parsed.homePageURL { feed.homePageURL = home }
        if let icon = parsed.iconURL { feed.iconURL = icon }
        feed.httpETag = fetched.etag
        feed.httpLastModified = fetched.lastModified
        feed.lastFetched = .now
        feed.lastFetchErrorDescription = nil

        var existing = Dictionary(feed.articles.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })

        for item in parsed.items {
            let guid = item.stableID()
            if let article = existing[guid] {
                update(article, from: item)
            } else {
                let article = makeArticle(from: item, guid: guid, feed: feed)
                context.insert(article)
                article.feed = feed
                for attachment in item.attachments {
                    let media = MediaAttachment(
                        url: attachment.url,
                        mimeType: attachment.mimeType,
                        title: attachment.title,
                        durationSeconds: attachment.duration,
                        byteCount: attachment.byteCount
                    )
                    context.insert(media)
                    media.article = article
                }
                existing[guid] = article
            }
        }

        prune(feed, context: context)
    }

    private func makeArticle(from item: ParsedItem, guid: String, feed: Feed) -> Article {
        let html = item.contentHTML ?? item.summaryHTML ?? ""
        let plain = HTMLTextExtractor.plainText(from: html)

        return Article(
            guid: guid,
            title: item.title ?? "Untitled",
            url: item.url,
            author: item.author,
            summaryHTML: item.summaryHTML,
            contentHTML: item.contentHTML,
            plainSummary: plain.truncated(to: 320),
            publishedAt: item.datePublished ?? item.dateModified ?? .now,
            updatedAt: item.dateModified,
            bannerImageURL: item.bannerImageURL,
            wordCount: plain.wordCount,
            tags: item.tags
        )
    }

    /// Publishers edit in place. Refresh the text, never the reader's own state.
    private func update(_ article: Article, from item: ParsedItem) {
        let incomingHTML = item.contentHTML ?? item.summaryHTML
        let currentHTML = article.contentHTML ?? article.summaryHTML
        guard incomingHTML != currentHTML || item.title != article.title else { return }

        if article.isPlaceholder {
            // A stub adopted from iCloud, meeting its actual contents for the
            // first time. Take everything the publisher offers.
            if let url = item.url { article.url = url }
            if let published = item.datePublished { article.publishedAt = published }
            if let author = item.author { article.author = author }
            article.isPlaceholder = false
        }

        if let title = item.title?.nilIfEmpty { article.title = title }
        if let content = item.contentHTML { article.contentHTML = content }
        if let summary = item.summaryHTML { article.summaryHTML = summary }
        if let modified = item.dateModified { article.updatedAt = modified }
        if let banner = item.bannerImageURL, article.bannerImageURL == nil { article.bannerImageURL = banner }

        let plain = HTMLTextExtractor.plainText(from: article.bestHTML ?? "")
        article.plainSummary = plain.truncated(to: 320)
        article.wordCount = plain.wordCount
        ArticleRenderer.shared.invalidate()
    }

    /// Keep the store honest: drop the oldest entries, but never a favourite.
    private func prune(_ feed: Feed, context: ModelContext) {
        let disposable = feed.articles
            .filter { !$0.isStarred }
            .sorted { $0.publishedAt > $1.publishedAt }
        guard disposable.count > Self.retentionLimit else { return }
        for article in disposable[Self.retentionLimit...] {
            context.delete(article)
        }
    }

    // MARK: - Subscribing

    @discardableResult
    func subscribe(to discovered: DiscoveredFeed, in context: ModelContext) -> Feed {
        let existing = (try? context.fetch(FetchDescriptor<Feed>()))?.first { $0.feedURL == discovered.url }
        if let existing { return existing }

        let count = (try? context.fetchCount(FetchDescriptor<Feed>())) ?? 0
        let feed = Feed(
            feedURL: discovered.url,
            title: discovered.title,
            feedDescription: discovered.subtitle,
            homePageURL: discovered.homePageURL,
            iconURL: discovered.iconURL,
            sortIndex: count
        )
        context.insert(feed)
        try? context.save()
        return feed
    }

}
