//
//  SpeechScript.swift
//  Feed Me, Seymour!
//
//  Turns a parsed article into something worth listening to.
//
//  This is the payoff for not using a web view. Because the article is already
//  a list of typed blocks, the script can skip what reads badly out loud (a
//  code listing, a pricing table), announce what would otherwise be a
//  mysterious silence (a photograph, a video), and speak captions and alt text
//  that a sighted reader gets for free.
//

import Foundation
import NaturalLanguage

struct SpeechSegment: Identifiable, Hashable {

    enum Role: Hashable {
        case title, byline, heading, paragraph, quote, attribution, listItem, caption, announcement
    }

    let id = UUID()
    var text: String
    var role: Role

    /// The block this came from, so the reader can scroll to it and light it up.
    var blockID: UUID?

    var preDelay: TimeInterval = 0
    var postDelay: TimeInterval = 0

    /// True only when `text` is character-for-character what that block renders,
    /// so a spoken range can be mapped straight back onto the words on screen.
    var tracksOnScreen: Bool = false
}

enum SpeechScript {

    /// Blocks whose contents are not prose. Reading a Swift listing aloud helps
    /// nobody; saying that one is there does.
    static func segments(article: Article, rendered: RenderedArticle, announcesImages: Bool) -> [SpeechSegment] {
        var segments: [SpeechSegment] = []

        segments.append(
            SpeechSegment(text: article.displayTitle, role: .title, postDelay: 0.55)
        )

        if let byline = byline(for: article) {
            segments.append(SpeechSegment(text: byline, role: .byline, postDelay: 0.5))
        }

        if announcesImages, let lead = rendered.leadImage, let description = describe(lead) {
            segments.append(SpeechSegment(text: description, role: .announcement, postDelay: 0.3))
        }

        append(rendered.blocks, to: &segments, announcesImages: announcesImages)

        return segments.filter { !$0.text.trimmed.isEmpty }
    }

    private static func byline(for article: Article) -> String? {
        let date = article.publishedAt.readerStamp
        if let author = article.author?.nilIfEmpty {
            return "By \(author). \(date)."
        }
        return "\(date)."
    }

    private static func append(_ blocks: [ArticleBlock], to segments: inout [SpeechSegment], announcesImages: Bool, depth: Int = 0) {
        for block in blocks {
            switch block.kind {

            case .paragraph(let text):
                segments.append(
                    SpeechSegment(
                        text: String(text.characters),
                        role: .paragraph,
                        blockID: block.id,
                        postDelay: 0.32,
                        tracksOnScreen: true
                    )
                )

            case .heading(_, let text):
                segments.append(
                    SpeechSegment(
                        text: String(text.characters),
                        role: .heading,
                        blockID: block.id,
                        preDelay: 0.5,
                        postDelay: 0.35,
                        tracksOnScreen: true
                    )
                )

            case .quote(let inner, let attribution):
                var quoted: [SpeechSegment] = []
                append(inner, to: &quoted, announcesImages: announcesImages, depth: depth + 1)
                for segment in quoted {
                    var quotedSegment = segment
                    quotedSegment.role = .quote
                    segments.append(quotedSegment)
                }
                if let attribution {
                    segments.append(
                        SpeechSegment(
                            text: String(attribution.characters),
                            role: .attribution,
                            blockID: block.id,
                            preDelay: 0.25,
                            postDelay: 0.4
                        )
                    )
                }

            case .list(let list):
                for (offset, item) in list.items.enumerated() {
                    var itemSegments: [SpeechSegment] = []
                    append(item, to: &itemSegments, announcesImages: announcesImages, depth: depth + 1)
                    guard !itemSegments.isEmpty else { continue }

                    // Number an ordered list the way a person would read it out.
                    if list.isOrdered {
                        itemSegments[0].text = "\(list.start + offset). \(itemSegments[0].text)"
                        itemSegments[0].tracksOnScreen = false
                    }
                    for segment in itemSegments {
                        var listSegment = segment
                        listSegment.role = .listItem
                        listSegment.blockID = block.id
                        listSegment.preDelay = max(listSegment.preDelay, 0.18)
                        segments.append(listSegment)
                    }
                }

            case .code(let code):
                let language = code.language?.nilIfEmpty
                segments.append(
                    SpeechSegment(
                        text: language.map { "\($0) code sample." } ?? "Code sample.",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.3,
                        postDelay: 0.3
                    )
                )

            case .table(let table):
                let rows = table.rows.count
                segments.append(
                    SpeechSegment(
                        text: "Table with \(rows) \(rows == 1 ? "row" : "rows").",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.3,
                        postDelay: 0.3
                    )
                )

            case .image(let image):
                guard announcesImages, let description = describe(image) else { continue }
                segments.append(
                    SpeechSegment(text: description, role: .caption, blockID: block.id, preDelay: 0.25, postDelay: 0.25)
                )

            case .gallery(let images):
                guard announcesImages else { continue }
                segments.append(
                    SpeechSegment(
                        text: "Gallery of \(images.count) images.",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.25,
                        postDelay: 0.25
                    )
                )

            case .video(let video):
                segments.append(
                    SpeechSegment(
                        text: video.title?.nilIfEmpty.map { "Video: \($0)." } ?? "Video.",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.3,
                        postDelay: 0.3
                    )
                )

            case .audio(let audio):
                segments.append(
                    SpeechSegment(
                        text: audio.title?.nilIfEmpty.map { "Audio: \($0)." } ?? "Audio clip.",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.3,
                        postDelay: 0.3
                    )
                )

            case .embed(let embed):
                segments.append(
                    SpeechSegment(
                        text: embed.title?.nilIfEmpty.map { "\(embed.provider.displayName): \($0)." }
                            ?? "\(embed.provider.displayName) embed.",
                        role: .announcement,
                        blockID: block.id,
                        preDelay: 0.3,
                        postDelay: 0.3
                    )
                )

            case .separator:
                // Silence reads better than a word here. Lengthen the next pause.
                if !segments.isEmpty {
                    segments[segments.count - 1].postDelay += 0.55
                }
            }
        }
    }

    private static func describe(_ image: ImageMedia) -> String? {
        if let caption = image.caption, !String(caption.characters).trimmed.isEmpty {
            return "Image. \(String(caption.characters))"
        }
        if let alt = image.altText?.nilIfEmpty {
            return "Image. \(alt)"
        }
        return nil
    }

    // MARK: - Language

    /// A French article should be read by a French voice. Sampling the opening
    /// paragraphs is enough and costs nothing.
    static func dominantLanguage(of segments: [SpeechSegment]) -> String? {
        let sample = segments
            .filter { $0.role == .paragraph || $0.role == .title }
            .prefix(6)
            .map(\.text)
            .joined(separator: " ")

        guard sample.count >= 40 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }

        // Don't act on a guess the recognizer isn't confident about.
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let confidence = hypotheses[language], confidence > 0.75 else { return nil }
        return language.rawValue
    }
}
