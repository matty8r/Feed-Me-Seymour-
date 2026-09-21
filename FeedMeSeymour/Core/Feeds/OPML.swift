//
//  OPML.swift
//  Feed Me, Seymour!
//
//  Subscriptions belong to the reader, not to the app. Import and export are
//  one tap each.
//

import Foundation

struct OPMLEntry: Hashable, Sendable {
    var title: String
    var feedURL: URL
    var homePageURL: URL?
}

enum OPML {

    // MARK: - Export

    static func document(for entries: [OPMLEntry], title: String = "Feed Me, Seymour! Subscriptions") -> String {
        let generated = ISO8601DateFormatter().string(from: .now)
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<opml version=\"2.0\">",
            "  <head>",
            "    <title>\(escape(title))</title>",
            "    <dateCreated>\(generated)</dateCreated>",
            "  </head>",
            "  <body>"
        ]
        for entry in entries.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            var attributes = "type=\"rss\" text=\"\(escape(entry.title))\" title=\"\(escape(entry.title))\" xmlUrl=\"\(escape(entry.feedURL.absoluteString))\""
            if let home = entry.homePageURL {
                attributes += " htmlUrl=\"\(escape(home.absoluteString))\""
            }
            lines.append("    <outline \(attributes)/>")
        }
        lines.append(contentsOf: ["  </body>", "</opml>", ""])
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Import

    static func entries(fromOPML data: Data) -> [OPMLEntry] {
        let parser = OPMLParser()
        return parser.parse(data)
    }
}

private final class OPMLParser: NSObject, XMLParserDelegate {
    private var entries: [OPMLEntry] = []

    func parse(_ data: Data) -> [OPMLEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        func value(_ key: String) -> String? {
            for (name, value) in attributes where name.lowercased() == key.lowercased() {
                return value.trimmed.nilIfEmpty
            }
            return nil
        }

        // Folders are outlines without an xmlUrl; we flatten them.
        guard let raw = value("xmlUrl") ?? value("xmlurl"), let url = URL(string: raw) else { return }
        let title = value("title") ?? value("text") ?? url.prettyHost
        let home = (value("htmlUrl") ?? value("htmlurl")).flatMap(URL.init(string:))
        entries.append(OPMLEntry(title: title, feedURL: url, homePageURL: home))
    }
}
