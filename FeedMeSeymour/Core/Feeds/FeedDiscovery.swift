//
//  FeedDiscovery.swift
//  Feed Me, Seymour!
//
//  People paste "theverge.com". Find the feed for them.
//

import Foundation

struct DiscoveredFeed: Identifiable, Hashable, Sendable {
    var id: URL { url }
    var url: URL
    var title: String
    var subtitle: String?
    var homePageURL: URL?
    var iconURL: URL?
    var sampleHeadlines: [String]
    var itemCount: Int
}

enum FeedDiscovery {

    /// Ordered best-guess addresses for whatever the reader typed.
    static func candidateURLs(for input: String) -> [URL] {
        var text = input.trimmed
        guard !text.isEmpty else { return [] }

        // Accept feed:// and news:// scheme handoffs from other apps.
        if let range = text.range(of: "^(feed|news)://", options: [.regularExpression, .caseInsensitive]) {
            text = "https://" + text[range.upperBound...]
        }
        if text.lowercased().hasPrefix("feed:") {
            text = String(text.dropFirst("feed:".count))
        }
        if !text.lowercased().hasPrefix("http") {
            text = "https://" + text
        }
        guard let base = URL(string: text) else { return [] }

        var candidates = [base]
        // Only probe the well-known paths when the reader gave us a bare site.
        let path = base.path
        if path.isEmpty || path == "/" {
            for suffix in ["feed", "rss", "feed.xml", "rss.xml", "atom.xml", "index.xml", "feeds/posts/default", "feed.json"] {
                if let candidate = URL(string: suffix, relativeTo: base)?.absoluteURL {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// Tries the address, then the addresses an HTML page advertises, then the
    /// conventional paths. Returns everything it could confirm.
    static func discover(from input: String, using fetcher: FeedFetcher = .shared) async -> [DiscoveredFeed] {
        let candidates = candidateURLs(for: input)
        guard let primary = candidates.first else { return [] }

        var found: [URL: DiscoveredFeed] = [:]

        if let confirmed = await confirm(url: primary, using: fetcher) {
            found[confirmed.url] = confirmed
            return Array(found.values)
        }

        // Not a feed — maybe it's the site. Read its <head> for alternates.
        if let (data, _) = try? await fetcher.data(from: primary),
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            let advertised = alternateFeedLinks(inHTML: html, baseURL: primary)
            for link in advertised.prefix(6) {
                if let confirmed = await confirm(url: link, using: fetcher) {
                    found[confirmed.url] = confirmed
                }
            }
        }

        if found.isEmpty {
            for candidate in candidates.dropFirst() {
                if let confirmed = await confirm(url: candidate, using: fetcher) {
                    found[confirmed.url] = confirmed
                    break
                }
            }
        }

        return found.values.sorted { $0.itemCount > $1.itemCount }
    }

    private static func confirm(url: URL, using fetcher: FeedFetcher) async -> DiscoveredFeed? {
        guard let outcome = try? await fetcher.fetch(url: url),
              case .fetched(let result) = outcome else { return nil }
        let feed = result.feed
        guard !feed.items.isEmpty || feed.title != nil else { return nil }

        return DiscoveredFeed(
            url: result.resolvedURL,
            title: feed.title?.nilIfEmpty ?? result.resolvedURL.prettyHost,
            subtitle: feed.subtitle,
            homePageURL: feed.homePageURL,
            iconURL: feed.iconURL,
            sampleHeadlines: feed.items.prefix(3).compactMap { $0.title },
            itemCount: feed.items.count
        )
    }

    /// `<link rel="alternate" type="application/rss+xml" href="…">`
    static func alternateFeedLinks(inHTML html: String, baseURL: URL?) -> [URL] {
        let head = String(html.prefix(200_000))
        var results: [URL] = []
        var seen = Set<URL>()

        let feedTypes = ["application/rss+xml", "application/atom+xml", "application/feed+json", "application/json", "text/xml", "application/xml"]
        let pattern = "<link\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

        let range = NSRange(head.startIndex..<head.endIndex, in: head)
        regex.enumerateMatches(in: head, options: [], range: range) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: head) else { return }
            let tag = String(head[tagRange])
            let lowered = tag.lowercased()
            guard lowered.contains("alternate") || lowered.contains("feed") else { return }
            guard feedTypes.contains(where: { lowered.contains($0) }) else { return }
            guard let href = attributeValue("href", in: tag), let url = URL.resolving(href, relativeTo: baseURL) else { return }
            if seen.insert(url).inserted { results.append(url) }
        }
        return results
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)) else { return nil }
        for index in [2, 3, 4] where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: tag) {
                return String(tag[range]).trimmed.nilIfEmpty
            }
        }
        return nil
    }
}
