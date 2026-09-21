//
//  XMLFeedParser.swift
//  Feed Me, Seymour!
//
//  One `XMLParser` delegate that speaks RSS 2.0, Atom 1.0 and RSS 1.0/RDF,
//  plus the namespaced extensions that carry the good stuff: content:encoded,
//  media:*, itunes:* and dublin core.
//
//  Namespace processing is deliberately *off*. Publishers bind prefixes
//  inconsistently (and sometimes not at all), so matching the qualified name as
//  written turns out to be both simpler and more forgiving.
//

import Foundation

final class XMLFeedParser: NSObject {

    private enum Format {
        case unknown, rss, atom, rdf
    }

    private var format: Format = .unknown
    private var feed = ParsedFeed()
    private var item: ParsedItem?

    private var elementPath: [String] = []
    private var text = ""

    private var isInsideItem = false
    private var isInsideChannelImage = false
    private var isInsideAuthor = false

    /// Atom `type="xhtml"` payloads arrive as live elements rather than escaped
    /// text, so we re-serialize them back into HTML.
    private var rawDepth = 0
    private var rawBuffer = ""
    private var rawTargetIsContent = true

    private var baseURL: URL?
    private var failure: Error?

    // MARK: - Entry point

    func parse(data: Data, sourceURL: URL? = nil) throws -> ParsedFeed {
        baseURL = sourceURL
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            // A feed that produced entries before blowing up is still worth showing.
            if !feed.items.isEmpty { return feed }
            if let failure { throw failure }
            let reason = parser.parserError?.localizedDescription ?? "unknown error"
            throw FeedParseError.malformedXML(reason)
        }
        guard format != .unknown else { throw FeedParseError.unrecognizedFormat }
        return feed
    }

    // MARK: - Helpers

    private func attribute(_ name: String, _ attributes: [String: String]) -> String? {
        if let exact = attributes[name] { return exact.nilIfEmpty }
        let lowered = name.lowercased()
        for (key, value) in attributes where key.lowercased() == lowered {
            return value.nilIfEmpty
        }
        return nil
    }

    private func url(_ candidate: String?) -> URL? {
        guard let candidate else { return nil }
        return URL.resolving(candidate, relativeTo: baseURL)
    }

    /// `content:encoded` -> `encoded`; `title` -> `title`.
    private func localName(_ qualified: String) -> String {
        guard let colon = qualified.firstIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: colon)...])
    }

    private func serializedStartTag(_ name: String, _ attributes: [String: String]) -> String {
        guard !attributes.isEmpty else { return "<\(name)>" }
        let rendered = attributes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\"\($0.value.replacingOccurrences(of: "\"", with: "&quot;"))\"" }
            .joined(separator: " ")
        return "<\(name) \(rendered)>"
    }

    private func appendAttachment(url attachmentURL: URL, mimeType: String?, title: String?, duration: TimeInterval?, bytes: Int?) {
        guard var current = item else { return }
        guard !current.attachments.contains(where: { $0.url == attachmentURL }) else { return }
        current.attachments.append(
            ParsedAttachment(url: attachmentURL, mimeType: mimeType, title: title, duration: duration, byteCount: bytes)
        )
        item = current
    }
}

// MARK: - XMLParserDelegate

extension XMLFeedParser: XMLParserDelegate {

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = (qName ?? elementName).lowercased()

        // Re-serializing an Atom xhtml payload: everything is markup, nothing is data.
        if rawDepth > 0 {
            rawBuffer += serializedStartTag(name, attributes)
            rawDepth += 1
            elementPath.append(name)
            return
        }

        elementPath.append(name)
        text = ""

        if let base = attribute("xml:base", attributes), let resolved = url(base) {
            baseURL = resolved
        }

        if format == .unknown {
            switch localName(name) {
            case "rss": format = .rss
            case "feed": format = .atom
            case "rdf": format = .rdf
            default: break
            }
        }

        switch name {
        case "item", "entry":
            isInsideItem = true
            item = ParsedItem()
            return

        case "image":
            // RSS channel artwork. Atom has no such element, and an <image> inside
            // an item is media, not branding.
            if !isInsideItem { isInsideChannelImage = true }

        case "author":
            isInsideAuthor = true

        case "link":
            handleLinkElement(attributes)

        case "enclosure":
            if let target = url(attribute("url", attributes)) {
                appendAttachment(
                    url: target,
                    mimeType: attribute("type", attributes),
                    title: attribute("title", attributes),
                    duration: nil,
                    bytes: attribute("length", attributes).flatMap(Int.init)
                )
            }

        case "media:content", "media:player":
            handleMediaContent(attributes)

        case "media:thumbnail", "itunes:image":
            if let target = url(attribute("url", attributes) ?? attribute("href", attributes)) {
                if isInsideItem {
                    if item?.bannerImageURL == nil { item?.bannerImageURL = target }
                } else if feed.iconURL == nil {
                    feed.iconURL = target
                }
            }

        case "category":
            // Atom puts the label in an attribute; RSS uses the element text.
            if isInsideItem, let term = attribute("term", attributes) ?? attribute("label", attributes) {
                item?.tags.append(term)
            }

        case "guid":
            break

        case "content", "summary", "description":
            if attribute("type", attributes)?.lowercased() == "xhtml" {
                rawDepth = 1
                rawBuffer = ""
                rawTargetIsContent = (localName(name) != "summary")
            }

        default:
            break
        }
    }

    private func handleLinkElement(_ attributes: [String: String]) {
        // RSS writes the destination as element text; Atom uses attributes.
        guard let href = attribute("href", attributes) else { return }
        let rel = (attribute("rel", attributes) ?? "alternate").lowercased()
        let type = attribute("type", attributes)

        switch rel {
        case "enclosure":
            if let target = url(href) {
                appendAttachment(
                    url: target,
                    mimeType: type,
                    title: attribute("title", attributes),
                    duration: nil,
                    bytes: attribute("length", attributes).flatMap(Int.init)
                )
            }

        case "alternate", "":
            // Prefer HTML over the twenty other representations a feed may list.
            let isHTML = type == nil || type!.localizedCaseInsensitiveContains("html")
            guard isHTML, let target = url(href) else { return }
            if isInsideItem {
                if item?.url == nil { item?.url = target }
            } else if feed.homePageURL == nil {
                feed.homePageURL = target
            }

        case "icon", "apple-touch-icon", "shortcut icon":
            if feed.iconURL == nil { feed.iconURL = url(href) }

        default:
            break // self, hub, next, replies, edit …
        }
    }

    private func handleMediaContent(_ attributes: [String: String]) {
        guard isInsideItem, let target = url(attribute("url", attributes)) else { return }
        let type = attribute("type", attributes)
        let medium = attribute("medium", attributes)?.lowercased()
        let duration = attribute("duration", attributes).flatMap(DateParser.duration(from:))
        let bytes = attribute("fileSize", attributes).flatMap(Int.init)

        // `medium="image"` with no thumbnail elsewhere makes a fine lead image.
        let kind = MediaKind.inferred(mimeType: type ?? medium.map { "\($0)/*" }, url: target)
        if kind == .image, item?.bannerImageURL == nil {
            item?.bannerImageURL = target
        }
        appendAttachment(url: target, mimeType: type, title: attribute("title", attributes), duration: duration, bytes: bytes)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if rawDepth > 0 {
            rawBuffer += string
        } else {
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8)
            ?? String(data: CDATABlock, encoding: .isoLatin1) else { return }
        if rawDepth > 0 {
            rawBuffer += string
        } else {
            text += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = (qName ?? elementName).lowercased()
        defer { if !elementPath.isEmpty { elementPath.removeLast() } }

        if rawDepth > 0 {
            rawDepth -= 1
            if rawDepth == 0 {
                let html = rawBuffer.trimmed.nilIfEmpty
                if isInsideItem {
                    if rawTargetIsContent { item?.contentHTML = html } else { item?.summaryHTML = html }
                }
                rawBuffer = ""
            } else {
                rawBuffer += "</\(name)>"
            }
            return
        }

        let value = text.trimmed
        text = ""

        switch name {
        case "item", "entry":
            finishItem()
            isInsideItem = false
            return

        case "image":
            isInsideChannelImage = false
            return

        case "author":
            // RSS puts the byline straight in the element; Atom nests a <name>.
            if isInsideItem, item?.author == nil, !value.isEmpty {
                item?.author = HTMLTextExtractor.plainText(from: value).squeezedWhitespace
            }
            isInsideAuthor = false
            return

        default:
            break
        }

        if isInsideItem {
            applyItemValue(name: name, value: value)
        } else {
            applyFeedValue(name: name, value: value)
        }
    }

    private func applyItemValue(name: String, value: String) {
        guard !value.isEmpty else { return }
        switch name {
        case "title", "media:title":
            if item?.title == nil { item?.title = value.squeezedWhitespace }

        case "link":
            // RSS: the permalink lives in the element text.
            if item?.url == nil, let target = url(value) { item?.url = target }

        case "guid", "id", "dc:identifier":
            if item?.guid == nil {
                item?.guid = value
                if item?.url == nil, value.lowercased().hasPrefix("http"), let target = url(value) {
                    item?.url = target
                }
            }

        case "pubdate", "published", "dc:date", "dcterms:created", "issued":
            if item?.datePublished == nil { item?.datePublished = DateParser.date(from: value) }

        case "updated", "lastmod", "dcterms:modified", "atom:updated":
            if item?.dateModified == nil { item?.dateModified = DateParser.date(from: value) }

        case "description", "summary", "itunes:summary", "media:description":
            if item?.summaryHTML == nil { item?.summaryHTML = value }

        case "content:encoded", "content", "content:html", "body", "xhtml:body":
            if item?.contentHTML == nil { item?.contentHTML = value }

        case "dc:creator", "itunes:author", "creator":
            if item?.author == nil { item?.author = value.squeezedWhitespace }

        case "name", "email":
            // Atom nests the byline: <author><name>…</name></author>
            if isInsideAuthor, name == "name", item?.author == nil {
                item?.author = value.squeezedWhitespace
            }

        case "itunes:duration":
            if let duration = DateParser.duration(from: value),
               let index = item?.attachments.firstIndex(where: { $0.duration == nil && $0.mimeType?.hasPrefix("audio") == true }) {
                item?.attachments[index].duration = duration
            }

        case "category", "dc:subject":
            item?.tags.append(value.squeezedWhitespace)

        default:
            break
        }
    }

    private func applyFeedValue(name: String, value: String) {
        guard !value.isEmpty else { return }
        switch name {
        case "title":
            if isInsideChannelImage { return }
            if feed.title == nil { feed.title = value.squeezedWhitespace }

        case "description", "subtitle", "itunes:summary", "info":
            if feed.subtitle == nil { feed.subtitle = value.squeezedWhitespace }

        case "link":
            if isInsideChannelImage { return }
            if feed.homePageURL == nil, let target = url(value) { feed.homePageURL = target }

        case "url":
            if isInsideChannelImage, feed.iconURL == nil { feed.iconURL = url(value) }

        case "icon", "logo":
            if feed.iconURL == nil { feed.iconURL = url(value) }

        default:
            break
        }
    }

    private func finishItem() {
        guard var finished = item else { return }
        item = nil

        // Podcast feeds routinely carry the runtime outside the enclosure.
        if finished.datePublished == nil { finished.datePublished = finished.dateModified }
        if finished.title == nil, let summary = finished.summaryHTML {
            finished.title = HTMLTextExtractor.plainText(from: summary).truncated(to: 80)
        }
        finished.tags = Array(Set(finished.tags)).sorted()
        feed.items.append(finished)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failure = FeedParseError.malformedXML(parseError.localizedDescription)
    }
}
