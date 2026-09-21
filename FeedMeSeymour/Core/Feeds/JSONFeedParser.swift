//
//  JSONFeedParser.swift
//  Feed Me, Seymour!
//
//  jsonfeed.org version 1.1.
//

import Foundation

enum JSONFeedParser {

    private struct Document: Decodable {
        var title: String?
        var description: String?
        var home_page_url: String?
        var icon: String?
        var favicon: String?
        var items: [Item]?

        struct Item: Decodable {
            var id: String?
            var url: String?
            var external_url: String?
            var title: String?
            var content_html: String?
            var content_text: String?
            var summary: String?
            var image: String?
            var banner_image: String?
            var date_published: String?
            var date_modified: String?
            var tags: [String]?
            var author: Author?
            var authors: [Author]?
            var attachments: [Attachment]?
        }

        struct Author: Decodable {
            var name: String?
        }

        struct Attachment: Decodable {
            var url: String?
            var mime_type: String?
            var title: String?
            var size_in_bytes: Int?
            var duration_in_seconds: Double?
        }
    }

    static func parse(data: Data, sourceURL: URL? = nil) throws -> ParsedFeed {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw FeedParseError.unrecognizedFormat
        }
        guard document.title != nil || document.items != nil else {
            throw FeedParseError.unrecognizedFormat
        }

        func resolve(_ candidate: String?) -> URL? {
            guard let candidate else { return nil }
            return URL.resolving(candidate, relativeTo: sourceURL)
        }

        var feed = ParsedFeed()
        feed.title = document.title?.squeezedWhitespace
        feed.subtitle = document.description?.squeezedWhitespace
        feed.homePageURL = resolve(document.home_page_url)
        feed.iconURL = resolve(document.icon ?? document.favicon)

        feed.items = (document.items ?? []).map { raw in
            var item = ParsedItem()
            item.guid = raw.id
            item.title = raw.title?.squeezedWhitespace
            item.url = resolve(raw.url ?? raw.external_url)
            item.contentHTML = raw.content_html ?? raw.content_text.map { text in
                // Content given as plain text still deserves paragraphs.
                text.components(separatedBy: "\n\n")
                    .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
                    .joined()
            }
            item.summaryHTML = raw.summary
            item.datePublished = DateParser.date(from: raw.date_published)
            item.dateModified = DateParser.date(from: raw.date_modified)
            item.bannerImageURL = resolve(raw.banner_image ?? raw.image)
            item.author = (raw.author?.name ?? raw.authors?.first?.name)?.squeezedWhitespace
            item.tags = raw.tags ?? []
            item.attachments = (raw.attachments ?? []).compactMap { attachment in
                guard let url = resolve(attachment.url) else { return nil }
                return ParsedAttachment(
                    url: url,
                    mimeType: attachment.mime_type,
                    title: attachment.title,
                    duration: attachment.duration_in_seconds,
                    byteCount: attachment.size_in_bytes
                )
            }
            return item
        }
        return feed
    }
}
