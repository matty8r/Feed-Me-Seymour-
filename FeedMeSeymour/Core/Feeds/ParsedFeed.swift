//
//  ParsedFeed.swift
//  Feed Me, Seymour!
//
//  Format-agnostic intermediate values. RSS, Atom, RDF and JSON Feed all land
//  here, and only this shape ever reaches SwiftData.
//

import Foundation

struct ParsedAttachment: Hashable, Sendable {
    var url: URL
    var mimeType: String?
    var title: String?
    var duration: TimeInterval?
    var byteCount: Int?
}

struct ParsedItem: Sendable {
    var guid: String?
    var title: String?
    var url: URL?
    var summaryHTML: String?
    var contentHTML: String?
    var author: String?
    var datePublished: Date?
    var dateModified: Date?
    var bannerImageURL: URL?
    var attachments: [ParsedAttachment] = []
    var tags: [String] = []

    /// Fall back to the entry's own HTML when the feed named no image of its
    /// own. Called once as each item finishes parsing, which is off the main
    /// actor — the merge that follows is not the place to be tokenising HTML.
    mutating func resolveBannerImage() {
        guard bannerImageURL == nil else { return }

        // An image enclosure is as good a thumbnail as one dug out of the
        // prose, and settling it here means the timeline never has to fault
        // the attachments relationship to find a picture.
        if let image = attachments.first(where: {
            MediaKind.inferred(mimeType: $0.mimeType, url: $0.url) == .image
        }) {
            bannerImageURL = image.url
            return
        }

        guard let html = contentHTML ?? summaryHTML else { return }
        bannerImageURL = ArticleContentParser.leadImageURL(inHTML: html, baseURL: url)
    }

    /// Identity within its feed. Publishers are inconsistent, so fall back in order.
    func stableID() -> String {
        if let guid = guid?.trimmed, !guid.isEmpty { return guid }
        if let url { return url.absoluteString }
        if let title = title?.trimmed, !title.isEmpty {
            return "title:\(title)|\(datePublished?.timeIntervalSince1970.rounded() ?? 0)"
        }
        return UUID().uuidString
    }
}

struct ParsedFeed: Sendable {
    var title: String?
    var subtitle: String?
    var homePageURL: URL?
    var iconURL: URL?
    var items: [ParsedItem] = []

    var isEmpty: Bool { title == nil && items.isEmpty }
}

enum FeedParseError: LocalizedError {
    case unrecognizedFormat
    case malformedXML(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            "That address doesn’t look like an RSS, Atom or JSON feed."
        case .malformedXML(let detail):
            "The feed is malformed: \(detail)"
        case .empty:
            "The feed parsed, but it has no entries."
        }
    }
}
