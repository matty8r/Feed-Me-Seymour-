//
//  ArticleRenderer.swift
//  Feed Me, Seymour!
//
//  Parsing HTML is cheap but not free, and the reader may flick through a
//  hundred articles. Render once, keep the result until memory gets tight.
//

import Foundation

struct RenderedArticle: Sendable {
    var leadImage: ImageMedia?
    var blocks: [ArticleBlock]

    var isEmpty: Bool { blocks.isEmpty && leadImage == nil }
    var wordCount: Int { blocks.wordCount }
}

@MainActor
final class ArticleRenderer {
    static let shared = ArticleRenderer()

    private let cache = NSCache<NSString, CacheBox>()

    private final class CacheBox {
        let value: RenderedArticle
        init(_ value: RenderedArticle) { self.value = value }
    }

    init() {
        cache.countLimit = 120
    }

    func render(_ article: Article) -> RenderedArticle {
        let html = article.bestHTML ?? ""
        let key = Self.cacheKey(for: article, html: html)
        if let cached = cache.object(forKey: key) { return cached.value }

        let rendered = Self.render(
            html: html,
            baseURL: article.url ?? article.feed?.homePageURL,
            bannerImageURL: article.bannerImageURL
        )
        cache.setObject(CacheBox(rendered), forKey: key)
        return rendered
    }

    /// Render an article before anyone asks to see it.
    ///
    /// Moving to the next article otherwise parses its HTML during the
    /// transition, which is exactly when the main thread has other things to
    /// do — the new text lands a beat late and the layout settles visibly.
    /// Parsing happens off the main actor; only the cache write comes back.
    func prepare(_ article: Article) {
        let html = article.bestHTML ?? ""
        let key = Self.cacheKey(for: article, html: html)
        guard cache.object(forKey: key) == nil else { return }

        let baseURL = article.url ?? article.feed?.homePageURL
        let banner = article.bannerImageURL

        Task.detached(priority: .utility) {
            let rendered = Self.render(html: html, baseURL: baseURL, bannerImageURL: banner)
            await MainActor.run {
                ArticleRenderer.shared.cache.setObject(CacheBox(rendered), forKey: key)
            }
        }
    }

    private static func cacheKey(for article: Article, html: String) -> NSString {
        "\(article.uuid.uuidString)-\(html.count)" as NSString
    }

    func invalidate() { cache.removeAllObjects() }

    nonisolated static func render(html: String, baseURL: URL?, bannerImageURL: URL?) -> RenderedArticle {
        var suppressed: Set<URL> = []
        if let bannerImageURL { suppressed.insert(bannerImageURL) }

        let parser = ArticleContentParser(baseURL: baseURL, suppressedImageURLs: suppressed)
        var blocks = parser.parse(html: html)

        var lead: ImageMedia?
        if let bannerImageURL {
            lead = ImageMedia(url: bannerImageURL)
        } else if let first = blocks.first, case .image(let image) = first.kind, image.caption == nil {
            // An article that opens on a photograph should open on that photograph.
            lead = image
            blocks.removeFirst()
        }

        return RenderedArticle(leadImage: lead, blocks: blocks)
    }
}
