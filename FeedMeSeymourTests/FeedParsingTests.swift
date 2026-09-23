//
//  FeedParsingTests.swift
//  Feed Me, Seymour! Tests
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Feed parsing")
struct FeedParsingTests {

    @Test("RSS 2.0 with namespaced extensions")
    func rss() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <title>Skid Row Gazette</title>
            <link>https://example.com</link>
            <description>Flowers and other business</description>
            <image><url>https://example.com/logo.png</url><title>Logo</title></image>
            <item>
              <title>Somewhere That's Green</title>
              <link>https://example.com/green</link>
              <guid isPermaLink="false">post-1</guid>
              <pubDate>Tue, 03 Jun 2025 09:39:21 GMT</pubDate>
              <dc:creator>Audrey</dc:creator>
              <description>A little development with a little picket fence.</description>
              <content:encoded><![CDATA[<p>A <strong>matchbox</strong> of our own.</p>]]></content:encoded>
              <media:thumbnail url="https://example.com/green.jpg"/>
              <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" length="12345"/>
              <category>Dreams</category>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), sourceURL: URL(string: "https://example.com/feed"))

        #expect(feed.title == "Skid Row Gazette")
        #expect(feed.iconURL?.absoluteString == "https://example.com/logo.png")
        #expect(feed.items.count == 1)

        let item = try #require(feed.items.first)
        #expect(item.title == "Somewhere That's Green")
        #expect(item.guid == "post-1")
        #expect(item.url?.absoluteString == "https://example.com/green")
        #expect(item.author == "Audrey")
        #expect(item.contentHTML?.contains("<strong>matchbox</strong>") == true)
        #expect(item.bannerImageURL?.absoluteString == "https://example.com/green.jpg")
        #expect(item.tags == ["Dreams"])
        #expect(item.attachments.count == 1)
        #expect(item.attachments.first?.mimeType == "audio/mpeg")
        #expect(item.attachments.first?.byteCount == 12345)

        let published = try #require(item.datePublished)
        #expect(abs(published.timeIntervalSince1970 - 1748943561) < 1)
    }

    @Test("Atom, including escaped and xhtml content")
    func atom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Mushnik's</title>
          <subtitle>Est. 1960</subtitle>
          <link rel="self" href="https://example.com/atom.xml"/>
          <link rel="alternate" type="text/html" href="https://example.com/"/>
          <entry>
            <title>Escaped entry</title>
            <id>tag:example.com,2025:1</id>
            <link rel="alternate" href="https://example.com/one"/>
            <updated>2025-06-03T09:39:21Z</updated>
            <author><name>Seymour Krelborn</name></author>
            <content type="html">&lt;p&gt;Hello&lt;/p&gt;</content>
          </entry>
          <entry>
            <title>XHTML entry</title>
            <id>tag:example.com,2025:2</id>
            <published>2025-06-02T08:00:00Z</published>
            <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Live <em>markup</em></p></div></content>
          </entry>
        </feed>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8))

        #expect(feed.title == "Mushnik's")
        #expect(feed.subtitle == "Est. 1960")
        // rel="self" must not become the home page.
        #expect(feed.homePageURL?.absoluteString == "https://example.com/")
        #expect(feed.items.count == 2)

        let first = feed.items[0]
        #expect(first.author == "Seymour Krelborn")
        #expect(first.contentHTML == "<p>Hello</p>")
        #expect(first.url?.absoluteString == "https://example.com/one")

        let second = feed.items[1]
        #expect(second.contentHTML?.contains("<em>markup</em>") == true)
    }

    @Test("JSON Feed")
    func jsonFeed() throws {
        let json = """
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Twoey's Notes",
          "home_page_url": "https://example.com",
          "items": [
            {
              "id": "1",
              "url": "https://example.com/1",
              "title": "Feed me",
              "content_html": "<p>Now.</p>",
              "date_published": "2025-06-03T09:39:21Z",
              "authors": [{ "name": "Audrey II" }],
              "attachments": [
                { "url": "https://example.com/a.mp3", "mime_type": "audio/mpeg", "duration_in_seconds": 91 }
              ]
            }
          ]
        }
        """
        let feed = try FeedParser.parse(data: Data(json.utf8), mimeType: "application/feed+json")

        #expect(feed.title == "Twoey's Notes")
        #expect(feed.items.first?.author == "Audrey II")
        #expect(feed.items.first?.attachments.first?.duration == 91)
    }

    @Test("Dates in the dialects feeds actually use", arguments: [
        "Tue, 03 Jun 2025 09:39:21 GMT",
        "2025-06-03T09:39:21Z",
        "2025-06-03T09:39:21.000Z",
        "2025-06-03T05:39:21-04:00"
    ])
    func dateParsing(_ raw: String) {
        let date = DateParser.date(from: raw)
        #expect(date != nil)
        #expect(abs((date?.timeIntervalSince1970 ?? 0) - 1748943561) < 1)
    }

    @Test("iTunes durations")
    func durations() {
        #expect(DateParser.duration(from: "1:02:03") == 3723)
        #expect(DateParser.duration(from: "62:03") == 3723)
        #expect(DateParser.duration(from: "3723") == 3723)
        #expect(DateParser.duration(from: "") == nil)
    }

    @Test("Garbage in, error out")
    func rejectsNonFeeds() {
        #expect(throws: (any Error).self) {
            try FeedParser.parse(data: Data("<html><body>hi</body></html>".utf8))
        }
    }

    @Test("Feed discovery reads <link rel=alternate>")
    func discovery() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml">
        <link rel="alternate" type="application/atom+xml" href="https://cdn.example.com/atom">
        <link rel="stylesheet" href="/site.css">
        </head><body></body></html>
        """
        let links = FeedDiscovery.alternateFeedLinks(inHTML: html, baseURL: URL(string: "https://example.com/blog/"))
        #expect(links.count == 2)
        #expect(links.first?.absoluteString == "https://example.com/feed.xml")
        #expect(links.last?.absoluteString == "https://cdn.example.com/atom")
    }

    @Test("Bare hostnames get the conventional paths tried")
    func candidates() {
        let candidates = FeedDiscovery.candidateURLs(for: "theverge.com")
        #expect(candidates.first?.absoluteString == "https://theverge.com")
        #expect(candidates.contains { $0.absoluteString.hasSuffix("/feed") })
        #expect(FeedDiscovery.candidateURLs(for: "feed://example.com/rss").first?.scheme == "https")
    }

    @Test("OPML round trip")
    func opml() {
        let entries = [
            OPMLEntry(title: "Daring & Fireball", feedURL: URL(string: "https://daringfireball.net/feeds/main")!, homePageURL: URL(string: "https://daringfireball.net")),
            OPMLEntry(title: "Kottke", feedURL: URL(string: "https://feeds.kottke.org/main")!, homePageURL: nil)
        ]
        let document = OPML.document(for: entries)
        #expect(document.contains("&amp;"))

        let parsed = OPML.entries(fromOPML: Data(document.utf8))
        #expect(parsed.count == 2)
        #expect(parsed.contains { $0.title == "Daring & Fireball" })
        #expect(parsed.contains { $0.feedURL.absoluteString == "https://feeds.kottke.org/main" })
    }
}

// MARK: - Lead images

@Suite("Lead images")
struct LeadImageTests {

    private func item(_ xml: String) -> ParsedItem? {
        try? FeedParser.parse(data: Data(xml.utf8)).items.first
    }

    private func rss(_ body: String) -> String {
        """
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel><title>A feed</title><item>
        <title>An entry</title><link>https://example.com/post</link>
        \(body)
        </item></channel></rss>
        """
    }

    @Test("A feed that names its own thumbnail keeps it")
    func explicitThumbnailWins() {
        let parsed = item(rss("""
        <media:thumbnail url="https://example.com/named.jpg"/>
        <description><![CDATA[<p><img src="https://example.com/inline.jpg"></p>]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/named.jpg")
    }

    @Test("Otherwise the first picture in the entry is used")
    func fallsBackToContent() {
        let parsed = item(rss("""
        <description><![CDATA[<p>Words first.</p><p><img src="https://example.com/hero.jpg" width="800" height="600"></p>]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/hero.jpg")
    }

    @Test("Relative sources resolve against the entry")
    func resolvesRelative() {
        let parsed = item(rss("""
        <description><![CDATA[<img src="/images/hero.jpg">]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/images/hero.jpg")
    }

    @Test("srcset picks the widest, like the reader does")
    func picksWidestInSrcset() {
        let parsed = item(rss("""
        <description><![CDATA[<img srcset="small.jpg 320w, large.jpg 1600w" src="small.jpg">]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/large.jpg")
    }

    @Test("Tracking pixels are passed over for the real picture")
    func skipsTrackingPixels() {
        let parsed = item(rss("""
        <description><![CDATA[
        <img src="https://feedburner.com/~ff/beacon.gif" width="1" height="1">
        <img src="https://example.com/spacer.gif">
        <img src="https://example.com/real.jpg">
        ]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/real.jpg")
    }

    @Test("An entry with no pictures gets no thumbnail")
    func noImages() {
        let parsed = item(rss("<description><![CDATA[<p>Only words.</p>]]></description>"))
        #expect(parsed?.bannerImageURL == nil)
    }

    @Test("A data: URI is not a thumbnail")
    func skipsDataURIs() {
        let parsed = item(rss("""
        <description><![CDATA[<img src="data:image/gif;base64,R0lGODlhAQAB"><img src="https://example.com/real.jpg">]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/real.jpg")
    }

    @Test("A lazy-loaded image still counts")
    func lazyLoaded() {
        let parsed = item(rss("""
        <description><![CDATA[<img data-src="https://example.com/lazy.jpg">]]></description>
        """))
        #expect(parsed?.bannerImageURL?.absoluteString == "https://example.com/lazy.jpg")
    }
}
