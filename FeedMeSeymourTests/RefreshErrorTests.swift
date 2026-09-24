//
//  RefreshErrorTests.swift
//  Feed Me, Seymour! Tests
//
//  What counts as a subscription failing, and what is only the app changing
//  its mind.
//

import Testing
import Foundation
import SwiftData
@testable import FeedMeSeymour

@Suite("Refresh failures")
struct RefreshErrorTests {

    /// URLSession reports an interrupted request this way, and its
    /// `localizedDescription` is the bare word "cancelled" — which is what
    /// used to appear in the status banner at launch, attributed to a feed
    /// that was perfectly fine.
    @Test("A cancelled URL request is not a failure")
    func urlCancellation() {
        let error = URLError(.cancelled)
        #expect(error.isCancellation)
    }

    @Test("A cancelled task is not a failure")
    func taskCancellation() {
        #expect(CancellationError().isCancellation)
    }

    @Test("Real network trouble still counts")
    func realFailures() {
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!URLError(.notConnectedToInternet).isCancellation)
        #expect(!URLError(.badServerResponse).isCancellation)
        #expect(!URLError(.cannotFindHost).isCancellation)
    }

    /// The same code on another domain means something else entirely, so the
    /// domain has to be part of the test.
    @Test("A matching code in another domain is not cancellation")
    func otherDomain() {
        let imposter = NSError(domain: "com.example.something", code: NSURLErrorCancelled)
        #expect(!imposter.isCancellation)
    }
}

/// Refreshing an article the app already has.
@MainActor
@Suite("Refresh backfills")
struct RefreshBackfillTests {

    private func makeArticle(bannerImageURL: URL? = nil) -> (Article, ModelContext) {
        let context = ModelContext(Persistence.makeInMemoryContainer())
        let feed = Feed(feedURL: URL(string: "https://branchesthreads.com/feed.xml")!, title: "Branches and Threads")
        context.insert(feed)
        let article = Article(
            guid: "https://branchesthreads.com/night-flowers.html",
            title: "Night flowers",
            summaryHTML: "<p><img src=\"https://branchesthreads.com/assets/night.jpg\" alt=\"night\"></p>",
            publishedAt: .now,
            bannerImageURL: bannerImageURL
        )
        context.insert(article)
        article.feed = feed
        return (article, context)
    }

    private func item(banner: URL?) -> ParsedItem {
        var item = ParsedItem()
        item.guid = "https://branchesthreads.com/night-flowers.html"
        item.title = "Night flowers"
        // Byte for byte what is already stored: the post has not been edited.
        item.summaryHTML = "<p><img src=\"https://branchesthreads.com/assets/night.jpg\" alt=\"night\"></p>"
        item.bannerImageURL = banner
        return item
    }

    /// The picture arrives from a later version of the parser, on an entry
    /// nobody has touched since it was saved. The guard that skips unchanged
    /// text must not carry the picture off with it.
    @Test("A missing picture is filled in even when the text has not changed")
    func backfillsBannerOnUnchangedArticle() {
        let (article, _) = makeArticle(bannerImageURL: nil)
        let banner = URL(string: "https://branchesthreads.com/assets/night.jpg")!

        FeedRefreshService().update(article, from: item(banner: banner))

        #expect(article.bannerImageURL == banner)
    }

    @Test("A picture already chosen is left alone")
    func doesNotOverwriteAnExistingBanner() {
        let chosen = URL(string: "https://branchesthreads.com/assets/chosen.jpg")!
        let (article, _) = makeArticle(bannerImageURL: chosen)

        FeedRefreshService().update(article, from: item(banner: URL(string: "https://example.com/other.jpg")!))

        #expect(article.bannerImageURL == chosen)
    }

    @Test("Nothing to backfill leaves the article as it was")
    func noBannerOffered() {
        let (article, _) = makeArticle(bannerImageURL: nil)
        FeedRefreshService().update(article, from: item(banner: nil))
        #expect(article.bannerImageURL == nil)
    }
}
