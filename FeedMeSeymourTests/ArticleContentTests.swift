//
//  ArticleContentTests.swift
//  Feed Me, Seymour! Tests
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Article content")
struct ArticleContentTests {

    private func parse(_ html: String, baseURL: String = "https://example.com/post/") -> [ArticleBlock] {
        ArticleContentParser(baseURL: URL(string: baseURL)).parse(html: html)
    }

    @Test("Paragraphs and inline emphasis")
    func paragraphs() {
        let blocks = parse("<p>Hello <strong>there</strong>, <em>friend</em>.</p><p>Second.</p>")
        #expect(blocks.count == 2)

        guard case .paragraph(let first) = blocks[0].kind else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(String(first.characters) == "Hello there, friend.")

        let strongRun = first.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(strongRun != nil)
        let emphasisRun = first.runs.first { $0.inlinePresentationIntent?.contains(.emphasized) == true }
        #expect(emphasisRun != nil)
    }

    @Test("Links keep their destination and resolve relative paths")
    func links() {
        let blocks = parse("<p>See <a href=\"/about\">about</a>.</p>")
        guard case .paragraph(let text) = blocks[0].kind else {
            Issue.record("expected a paragraph")
            return
        }
        let link = text.runs.compactMap(\.link).first
        #expect(link?.absoluteString == "https://example.com/about")
    }

    @Test("Entities become real punctuation")
    func entities() {
        #expect(HTMLEntities.decode("It&rsquo;s &mdash; fine &amp; good &#8212; yes &#x27;so&#x27;")
            == "It’s — fine & good — yes 'so'")
        #expect(HTMLEntities.decode("5 &notanentity; 6") == "5 &notanentity; 6")
    }

    @Test("Headings, rules and quotes")
    func structure() {
        let blocks = parse("""
        <h2>Act One</h2>
        <blockquote><p>Feed me.</p><cite>Audrey II</cite></blockquote>
        <hr>
        <p>After.</p>
        """)

        guard case .heading(let level, let heading) = blocks[0].kind else {
            Issue.record("expected a heading")
            return
        }
        #expect(level == 2)
        #expect(String(heading.characters) == "Act One")

        guard case .quote(let inner, let attribution) = blocks[1].kind else {
            Issue.record("expected a quote")
            return
        }
        #expect(inner.count == 1)
        #expect(String(attribution?.characters ?? "") == "Audrey II")
        #expect(blocks.contains { if case .separator = $0.kind { return true } else { return false } })
    }

    @Test("Lists, ordered and not")
    func lists() {
        let blocks = parse("<ul><li>One</li><li>Two</li></ul><ol start=\"3\"><li>Three</li></ol>")
        #expect(blocks.count == 2)

        guard case .list(let unordered) = blocks[0].kind else {
            Issue.record("expected a list")
            return
        }
        #expect(unordered.isOrdered == false)
        #expect(unordered.items.count == 2)

        guard case .list(let ordered) = blocks[1].kind else {
            Issue.record("expected a list")
            return
        }
        #expect(ordered.isOrdered)
        #expect(ordered.start == 3)
    }

    @Test("Images take the widest srcset candidate and carry their caption")
    func images() {
        let blocks = parse("""
        <figure>
          <img src="small.jpg" srcset="small.jpg 320w, large.jpg 1600w" alt="A plant" width="1600" height="900">
          <figcaption>Mean green mother</figcaption>
        </figure>
        """)
        guard case .image(let image) = blocks[0].kind else {
            Issue.record("expected an image")
            return
        }
        #expect(image.url.absoluteString == "https://example.com/post/large.jpg")
        #expect(image.altText == "A plant")
        #expect(String(image.caption?.characters ?? "") == "Mean green mother")
        #expect(image.aspectRatio == 1600.0 / 900.0)
    }

    @Test("Lazy-loaded images are found and tracking pixels are not")
    func lazyImages() {
        let blocks = parse("""
        <p><img data-src="hero.jpg" width="800" height="600"></p>
        <img src="https://feeds.feedburner.com/~r/pixel.gif" width="1" height="1">
        """)
        let images = blocks.compactMap { block -> ImageMedia? in
            if case .image(let image) = block.kind { return image }
            return nil
        }
        #expect(images.count == 1)
        #expect(images[0].url.lastPathComponent == "hero.jpg")
    }

    @Test("Three loose images become a gallery")
    func galleries() {
        let blocks = parse("<p><img src=\"a.jpg\"><img src=\"b.jpg\"><img src=\"c.jpg\"></p>")
        #expect(blocks.count == 1)
        guard case .gallery(let images) = blocks[0].kind else {
            Issue.record("expected a gallery")
            return
        }
        #expect(images.count == 3)
    }

    @Test("Video picks a source AVFoundation can open")
    func video() {
        let blocks = parse("""
        <video poster="poster.jpg">
          <source src="clip.webm" type="video/webm">
          <source src="clip.mp4" type="video/mp4">
        </video>
        """)
        guard case .video(let media) = blocks[0].kind else {
            Issue.record("expected a video")
            return
        }
        #expect(media.url.lastPathComponent == "clip.mp4")
        #expect(media.posterURL?.lastPathComponent == "poster.jpg")
    }

    @Test("Audio elements become audio blocks")
    func audio() {
        let blocks = parse("<audio src=\"show.mp3\" title=\"Episode 1\"></audio>")
        guard case .audio(let media) = blocks[0].kind else {
            Issue.record("expected audio")
            return
        }
        #expect(media.url.lastPathComponent == "show.mp3")
        #expect(media.title == "Episode 1")
    }

    @Test("Iframes become embeds, and YouTube is recognized")
    func embeds() {
        let blocks = parse("<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ\" width=\"560\" height=\"315\"></iframe>")
        guard case .embed(let embed) = blocks[0].kind else {
            Issue.record("expected an embed")
            return
        }
        #expect(embed.provider == .youTube)
        #expect(embed.youTubeID == "dQw4w9WgXcQ")
        #expect(embed.canonicalURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(abs(embed.aspectRatio - 560.0 / 315.0) < 0.001)
    }

    @Test("Preformatted code keeps its whitespace")
    func code() {
        let blocks = parse("<pre><code class=\"language-swift\">let x = 1\n    let y = 2</code></pre>")
        guard case .code(let code) = blocks[0].kind else {
            Issue.record("expected code")
            return
        }
        #expect(code.language == "swift")
        #expect(code.text == "let x = 1\n    let y = 2")
    }

    @Test("Script and style never reach the reader")
    func scriptsAreDropped() {
        let blocks = parse("<p>Before</p><script>var x = '<p>nope</p>';</script><style>p{color:red}</style><p>After</p>")
        #expect(blocks.count == 2)
        #expect(blocks.plainText == "Before\n\nAfter")
    }

    @Test("Double <br> is treated as a paragraph break")
    func brBreaks() {
        let blocks = parse("<div>One line.<br><br>Another line.</div>")
        #expect(blocks.count == 2)
    }

    @Test("Tables keep their headers")
    func tables() {
        let blocks = parse("""
        <table>
          <tr><th>Plant</th><th>Diet</th></tr>
          <tr><td>Audrey II</td><td>Blood</td></tr>
        </table>
        """)
        guard case .table(let table) = blocks[0].kind else {
            Issue.record("expected a table")
            return
        }
        #expect(table.headers.map { String($0.characters) } == ["Plant", "Diet"])
        #expect(table.rows.count == 1)
        #expect(table.columnCount == 2)
    }

    @Test("Malformed markup still produces readable prose")
    func malformed() {
        let blocks = parse("<p>Unclosed <b>bold<p>and a new paragraph<ul><li>item")
        #expect(!blocks.isEmpty)
        #expect(blocks.plainText.contains("new paragraph"))
        #expect(blocks.plainText.contains("item"))
    }

    @Test("The lead image is lifted out of the body")
    func leadImage() {
        let rendered = ArticleRenderer.render(
            html: "<img src=\"https://example.com/lead.jpg\"><p>Body copy.</p>",
            baseURL: URL(string: "https://example.com/post/"),
            bannerImageURL: nil
        )
        #expect(rendered.leadImage?.url.absoluteString == "https://example.com/lead.jpg")
        #expect(rendered.blocks.count == 1)
    }

    @Test("Plain text extraction for list summaries")
    func plainText() {
        let text = HTMLTextExtractor.plainText(from: "<p>Hello</p><p>World &amp; friends</p>")
        #expect(text == "Hello World & friends")
    }

    @Test("Superscript footnote markers are raised")
    func superscripts() {
        let blocks = parse("<p>Fact<sup>1</sup></p>")
        #expect(blocks.plainText == "Fact¹")
    }
}
