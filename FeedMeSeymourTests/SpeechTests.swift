//
//  SpeechTests.swift
//  Feed Me, Seymour! Tests
//
//  The script is the interesting half of read-aloud: what gets spoken, what
//  gets announced, what gets skipped, and whether the spoken text still lines
//  up with the words on screen.
//

import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import FeedMeSeymour

@MainActor
@Suite("Read aloud")
struct SpeechTests {

    private func makeArticle(title: String = "Somewhere That's Green", author: String? = "Audrey") -> Article {
        let context = ModelContext(Persistence.makeInMemoryContainer())
        let article = Article(
            guid: "a",
            title: title,
            author: author,
            publishedAt: Date(timeIntervalSince1970: 1_748_943_561)
        )
        context.insert(article)
        return article
    }

    private func script(_ html: String, announcesImages: Bool = true, title: String = "Somewhere That's Green") -> [SpeechSegment] {
        let rendered = ArticleRenderer.render(
            html: html,
            baseURL: URL(string: "https://example.com/post/"),
            bannerImageURL: nil
        )
        return SpeechScript.segments(
            article: makeArticle(title: title),
            rendered: rendered,
            announcesImages: announcesImages
        )
    }

    // MARK: - Shape

    @Test("The title and byline come first")
    func opensWithTitleAndByline() {
        let segments = script("<p>A matchbox of our own.</p>")

        #expect(segments.first?.role == .title)
        #expect(segments.first?.text == "Somewhere That's Green")
        #expect(segments.dropFirst().first?.role == .byline)
        #expect(segments.dropFirst().first?.text.contains("By Audrey") == true)
    }

    @Test("A missing byline is not spoken as an empty one")
    func handlesMissingAuthor() {
        let rendered = ArticleRenderer.render(html: "<p>Text.</p>", baseURL: nil, bannerImageURL: nil)
        let segments = SpeechScript.segments(
            article: makeArticle(author: nil),
            rendered: rendered,
            announcesImages: false
        )
        let byline = segments.first { $0.role == .byline }
        #expect(byline != nil)
        #expect(byline?.text.contains("By ") == false)
    }

    // MARK: - What is spoken verbatim

    @Test("Paragraph text matches the words on screen character for character")
    func paragraphsTrackTheScreen() {
        let html = "<p>Hello <strong>there</strong>, <em>friend</em> &mdash; it&rsquo;s fine.</p>"
        let rendered = ArticleRenderer.render(html: html, baseURL: nil, bannerImageURL: nil)
        let segments = SpeechScript.segments(article: makeArticle(), rendered: rendered, announcesImages: false)

        guard let block = rendered.blocks.first, case .paragraph(let text) = block.kind else {
            Issue.record("expected a paragraph block")
            return
        }
        guard let spoken = segments.first(where: { $0.role == .paragraph }) else {
            Issue.record("expected a spoken paragraph")
            return
        }

        // This equality is what lets a spoken range be mapped back onto the
        // rendered AttributedString to highlight the current word.
        #expect(spoken.text == String(text.characters))
        #expect(spoken.tracksOnScreen)
        #expect(spoken.blockID == block.id)
    }

    @Test("Headings are spoken, with a pause before them")
    func headingsGetRoom() {
        let segments = script("<p>One.</p><h2>Act Two</h2><p>Two.</p>")
        guard let heading = segments.first(where: { $0.role == .heading }) else {
            Issue.record("expected a heading")
            return
        }
        #expect(heading.text == "Act Two")
        #expect(heading.preDelay > 0)
    }

    @Test("A quotation's attribution is read after it")
    func readsAttribution() {
        let segments = script("<blockquote><p>Feed me.</p><cite>Audrey II</cite></blockquote>")
        #expect(segments.contains { $0.role == .quote && $0.text == "Feed me." })
        #expect(segments.contains { $0.role == .attribution && $0.text == "Audrey II" })
    }

    @Test("An ordered list is numbered aloud")
    func numbersOrderedLists() {
        let segments = script("<ol start=\"3\"><li>Water it</li><li>Feed it</li></ol>")
        let items = segments.filter { $0.role == .listItem }
        #expect(items.count == 2)
        #expect(items.first?.text == "3. Water it")
        #expect(items.last?.text == "4. Feed it")
        // Renumbered text no longer matches the screen, so it must not claim to.
        #expect(items.first?.tracksOnScreen == false)
    }

    @Test("An unordered list is read plainly")
    func readsUnorderedLists() {
        let segments = script("<ul><li>Blood</li></ul>")
        let items = segments.filter { $0.role == .listItem }
        #expect(items.first?.text == "Blood")
        #expect(items.first?.tracksOnScreen == true)
    }

    // MARK: - What is announced rather than read

    @Test("Code is announced, never read out")
    func announcesCode() {
        let segments = script("<pre><code class=\"language-swift\">let x = 1</code></pre>")
        let spoken = segments.map(\.text).joined(separator: " ")
        #expect(spoken.contains("swift code sample"))
        #expect(!spoken.contains("let x = 1"))
    }

    @Test("Tables are announced with their size")
    func announcesTables() {
        let html = "<table><tr><th>Plant</th></tr><tr><td>Audrey II</td></tr><tr><td>Fern</td></tr></table>"
        let segments = script(html)
        #expect(segments.contains { $0.text == "Table with 2 rows." })
    }

    @Test("Video and embeds are announced so the silence makes sense")
    func announcesMedia() {
        let segments = script("<iframe src=\"https://www.youtube.com/embed/abc\"></iframe>")
        #expect(segments.contains { $0.text.contains("YouTube") })
    }

    // MARK: - Images

    @Test("Images are described when asked, and skipped when not")
    func describesImages() {
        let html = "<figure><img src=\"a.jpg\" alt=\"A mean green mother\"></figure>"

        let described = script(html, announcesImages: true)
        #expect(described.contains { $0.text.contains("A mean green mother") })

        let silent = script(html, announcesImages: false)
        #expect(!silent.contains { $0.text.contains("mean green mother") })
    }

    @Test("An image with no alt text or caption is not announced as nothing")
    func skipsUndescribedImages() {
        let segments = script("<p>Before</p><img src=\"a.jpg\"><p>After</p>")
        #expect(!segments.contains { $0.role == .caption })
    }

    // MARK: - Pauses

    @Test("A section break becomes silence, not a spoken word")
    func separatorsBecomePauses() {
        let plain = script("<p>One.</p><p>Two.</p>")
        let broken = script("<p>One.</p><hr><p>Two.</p>")

        #expect(plain.count == broken.count)
        let plainFirst = plain.first { $0.text == "One." }
        let brokenFirst = broken.first { $0.text == "One." }
        #expect((brokenFirst?.postDelay ?? 0) > (plainFirst?.postDelay ?? 0))
    }

    @Test("Empty segments never reach the synthesizer")
    func dropsEmptySegments() {
        let segments = script("<p></p><p>   </p><p>Real text.</p>")
        #expect(segments.allSatisfy { !$0.text.trimmed.isEmpty })
    }

    // MARK: - Rate and language

    @Test("Rate multipliers stay inside what AVSpeechUtterance accepts")
    func clampsRate() {
        let slowest = SpeechReader.synthesizerRate(for: 0.1)
        let normal = SpeechReader.synthesizerRate(for: 1.0)
        let fastest = SpeechReader.synthesizerRate(for: 4.0)

        #expect(slowest >= AVSpeechUtteranceMinimumSpeechRate)
        #expect(fastest <= AVSpeechUtteranceMaximumSpeechRate)
        #expect(slowest < normal)
        #expect(normal < fastest)
        #expect(abs(normal - AVSpeechUtteranceDefaultSpeechRate) < 0.001)
    }

    @Test("Language detection needs enough text to be worth trusting")
    func ignoresShortSamples() {
        let short = [SpeechSegment(text: "Hi.", role: .paragraph)]
        #expect(SpeechScript.dominantLanguage(of: short) == nil)
    }

    @Test("A clearly English article is detected as English")
    func detectsEnglish() {
        let segments = [
            SpeechSegment(
                text: "The shop had been quiet all morning, and the rain against the window "
                    + "made the whole street look like something remembered rather than seen.",
                role: .paragraph
            )
        ]
        #expect(SpeechScript.dominantLanguage(of: segments) == "en")
    }
}
