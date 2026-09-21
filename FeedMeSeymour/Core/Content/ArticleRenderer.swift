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
        let key = "\(article.uuid.uuidString)-\(html.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        let rendered = Self.render(
            html: html,
            baseURL: article.url ?? article.feed?.homePageURL,
            bannerImageURL: article.bannerImageURL
        )
        cache.setObject(CacheBox(rendered), forKey: key)
        return rendered
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
