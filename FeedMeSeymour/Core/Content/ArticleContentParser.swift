//
//  ArticleContentParser.swift
//  Feed Me, Seymour!
//
//  Turns feed HTML into `ArticleBlock`s. Everything downstream of this file is
//  native SwiftUI — which is the whole reason the reader can have real
//  typography, real Dynamic Type and real AVKit controls.
//

import Foundation

struct ArticleContentParser {

    var baseURL: URL?
    /// Images already shown as the article's lead, so we don't print them twice.
    var suppressedImageURLs: Set<URL> = []

    init(baseURL: URL? = nil, suppressedImageURLs: Set<URL> = []) {
        self.baseURL = baseURL
        self.suppressedImageURLs = suppressedImageURLs
    }

    func parse(html: String) -> [ArticleBlock] {
        guard !html.trimmed.isEmpty else { return [] }
        let builder = Builder(baseURL: baseURL, suppressedImageURLs: suppressedImageURLs)
        builder.consume(HTMLTokenizer.tokenize(html))
        return Self.tidy(builder.finish())
    }

    // MARK: - Post-processing

    /// The first real picture in an entry's own HTML.
    ///
    /// Plenty of feeds carry no thumbnail of their own — no media:thumbnail, no
    /// itunes:image, no image enclosure — and put the picture in the entry body
    /// instead, which is where most of the web's writing keeps it. Reuses the
    /// same URL resolution and the same junk filter as the reader, so what the
    /// timeline shows is the picture the article opens with, and stops at the
    /// first hit rather than building the whole document.
    static func leadImageURL(inHTML html: String, baseURL: URL?) -> URL? {
        for token in HTMLTokenizer.tokenize(html) {
            guard case .startTag(let name, let attributes, _) = token,
                  name == "img" || name == "source" else { continue }
            guard let url = Builder.mediaURL(from: attributes, baseURL: baseURL) else { continue }

            var candidate = ImageMedia(url: url)
            candidate.pixelWidth = attributes["width"].flatMap { Int($0.filter(\.isNumber)) }
            candidate.pixelHeight = attributes["height"].flatMap { Int($0.filter(\.isNumber)) }
            guard !candidate.isProbablyDecorative else { continue }

            return url
        }
        return nil
    }

    static func tidy(_ blocks: [ArticleBlock]) -> [ArticleBlock] {
        var cleaned: [ArticleBlock] = []

        for block in blocks {
            switch block.kind {
            case .paragraph(let text) where String(text.characters).trimmed.isEmpty:
                continue
            case .separator:
                if case .some(.separator) = cleaned.last?.kind { continue }
                if cleaned.isEmpty { continue }
                cleaned.append(block)
            case .quote(let inner, let attribution):
                let tidied = tidy(inner)
                guard !tidied.isEmpty else { continue }
                cleaned.append(ArticleBlock(.quote(blocks: tidied, attribution: attribution), id: block.id))
            case .list(var list):
                list.items = list.items.map(tidy).filter { !$0.isEmpty }
                guard !list.items.isEmpty else { continue }
                cleaned.append(ArticleBlock(.list(list), id: block.id))
            default:
                cleaned.append(block)
            }
        }

        while case .some(.separator) = cleaned.last?.kind { cleaned.removeLast() }
        return groupGalleries(cleaned)
    }

    /// Three or more bare images in a row read better as a grid than as a stack.
    private static func groupGalleries(_ blocks: [ArticleBlock]) -> [ArticleBlock] {
        var output: [ArticleBlock] = []
        var run: [ImageMedia] = []

        func flushRun() {
            if run.count >= 3 {
                output.append(ArticleBlock(.gallery(run)))
            } else {
                output.append(contentsOf: run.map { ArticleBlock(.image($0)) })
            }
            run.removeAll()
        }

        for block in blocks {
            if case .image(let image) = block.kind, image.caption == nil {
                run.append(image)
            } else {
                flushRun()
                output.append(block)
            }
        }
        flushRun()
        return output
    }
}

// MARK: - Builder

private final class Builder {

    private final class Container {
        let tag: String
        var blocks: [ArticleBlock] = []
        var listIsOrdered = false
        var listStart = 1
        var listItems: [[ArticleBlock]] = []
        var tableHeaders: [AttributedString] = []
        var tableRows: [[AttributedString]] = []
        var currentRow: [AttributedString] = []
        var rowIsHeader = false
        var attribution: AttributedString?
        init(tag: String) { self.tag = tag }
    }

    private let baseURL: URL?
    private let suppressedImageURLs: Set<URL>

    private var stack: [Container] = [Container(tag: "root")]
    private var inline = AttributedString()

    private var boldDepth = 0
    private var italicDepth = 0
    private var codeDepth = 0
    private var strikeDepth = 0
    private var superscriptDepth = 0
    private var subscriptDepth = 0
    /// Optional entries keep `<a name="…">` anchors from inheriting the enclosing link.
    private var linkStack: [URL?] = []

    private var textTag = "p"

    private var isInPre = false
    private var preBuffer = ""
    private var preLanguage: String?

    private var isCapturingCite = false
    private var isInsideCite = false
    private var isCapturingCaption = false
    private var isInTableCell = false

    private var pendingVideo: VideoMedia?
    private var pendingAudio: AudioMedia?
    private var pendingSourceURL: URL?
    private var pendingPictureSource: URL?

    init(baseURL: URL?, suppressedImageURLs: Set<URL>) {
        self.baseURL = baseURL
        self.suppressedImageURLs = suppressedImageURLs
    }

    private var top: Container { stack[stack.count - 1] }

    // MARK: Token loop

    func consume(_ tokens: [HTMLToken]) {
        for token in tokens {
            switch token {
            case .text(let text):
                appendText(text)
            case .startTag(let name, let attributes, let isSelfClosing):
                startTag(name, attributes)
                if isSelfClosing, !HTMLTokenizer.voidTags.contains(name) {
                    endTag(name)
                }
            case .endTag(let name):
                endTag(name)
            }
        }
    }

    func finish() -> [ArticleBlock] {
        while stack.count > 1 { closeTop() }
        flushInline()
        return stack[0].blocks
    }

    // MARK: Inline text

    private var attributeContainer: AttributeContainer {
        var container = AttributeContainer()
        var intent: InlinePresentationIntent = []
        if boldDepth > 0 { intent.insert(.stronglyEmphasized) }
        if italicDepth > 0 { intent.insert(.emphasized) }
        if codeDepth > 0 { intent.insert(.code) }
        if strikeDepth > 0 { intent.insert(.strikethrough) }
        if !intent.isEmpty { container.inlinePresentationIntent = intent }
        if let link = currentLink { container.link = link }
        return container
    }

    private var currentLink: URL? {
        linkStack.last(where: { $0 != nil }) ?? nil
    }

    private func appendText(_ raw: String) {
        if isInPre {
            preBuffer += raw
            return
        }

        var text = Self.collapsingWhitespace(raw)
        guard !text.isEmpty else { return }

        if superscriptDepth > 0 { text = Self.superscripted(text) }
        if subscriptDepth > 0 { text = Self.subscripted(text) }

        // Don't open a paragraph with a space.
        if text == " ", inline.characters.isEmpty { return }
        if text.hasPrefix(" "), inline.characters.last == " " { text.removeFirst() }
        guard !text.isEmpty else { return }

        inline.append(AttributedString(text, attributes: attributeContainer))
    }

    private func flushInline() {
        let trimmed = Self.trimming(inline)
        inline = AttributedString()
        guard !String(trimmed.characters).trimmed.isEmpty else { return }

        if isCapturingCite {
            top.attribution = trimmed
            return
        }

        if textTag.count == 2, textTag.hasPrefix("h"), let level = Int(textTag.dropFirst()) {
            top.blocks.append(ArticleBlock(.heading(level: min(max(level, 1), 6), text: trimmed)))
            return
        }

        // A block written with <br><br> instead of <p> still deserves paragraphs.
        for paragraph in Self.splittingOnBlankLines(trimmed) {
            top.blocks.append(ArticleBlock(.paragraph(paragraph)))
        }
    }

    // MARK: Containers

    private func push(_ tag: String) {
        flushInline()
        stack.append(Container(tag: tag))
    }

    @discardableResult
    private func closeTop() -> Bool {
        flushInline()
        guard stack.count > 1 else { return false }
        let container = stack.removeLast()
        let parent = top

        switch container.tag {
        case "blockquote", "aside":
            if !container.blocks.isEmpty {
                parent.blocks.append(ArticleBlock(.quote(blocks: container.blocks, attribution: container.attribution)))
            }

        case "ul", "ol":
            var items = container.listItems
            if !container.blocks.isEmpty { items.append(container.blocks) }
            if !items.isEmpty {
                parent.blocks.append(
                    ArticleBlock(.list(ListBlock(isOrdered: container.listIsOrdered, start: container.listStart, items: items)))
                )
            }

        case "li":
            if parent.tag == "ul" || parent.tag == "ol" {
                parent.listItems.append(container.blocks)
            } else {
                parent.blocks.append(contentsOf: container.blocks)
            }

        case "table":
            finishRow(in: container)
            if !container.tableHeaders.isEmpty || !container.tableRows.isEmpty {
                parent.blocks.append(
                    ArticleBlock(.table(TableBlock(headers: container.tableHeaders, rows: container.tableRows, caption: container.attribution)))
                )
            }

        default:
            parent.blocks.append(contentsOf: container.blocks)
        }
        return true
    }

    /// Closes up to and including the nearest open container with this tag.
    private func closeContainer(_ tag: String) {
        guard stack.dropFirst().contains(where: { $0.tag == tag }) else { return }
        while stack.count > 1 {
            let wasMatch = top.tag == tag
            closeTop()
            if wasMatch { return }
        }
    }

    private func finishRow(in container: Container) {
        guard !container.currentRow.isEmpty else { return }
        if container.rowIsHeader, container.tableHeaders.isEmpty {
            container.tableHeaders = container.currentRow
        } else {
            container.tableRows.append(container.currentRow)
        }
        container.currentRow = []
        container.rowIsHeader = false
    }

    // MARK: Start tags

    private func startTag(_ name: String, _ attributes: [String: String]) {
        if isInPre {
            if name == "br" { preBuffer += "\n" }
            if name == "code", preLanguage == nil { preLanguage = Self.language(from: attributes) }
            return
        }

        switch name {
        // Inline emphasis
        case "strong", "b": boldDepth += 1
        case "em", "i", "var", "dfn": italicDepth += 1
        case "code", "kbd", "samp", "tt": codeDepth += 1
        case "del", "s", "strike": strikeDepth += 1
        case "sup": superscriptDepth += 1
        case "sub": subscriptDepth += 1

        case "cite":
            // Inside a quotation a <cite> is the attribution; elsewhere it's a title.
            if top.tag == "blockquote" {
                flushInline()
                isInsideCite = true
            } else {
                italicDepth += 1
            }

        case "a":
            linkStack.append(URL.resolving(attributes["href"] ?? "", relativeTo: baseURL))

        case "br":
            inline.append(AttributedString("\n"))

        case "wbr":
            break

        // Headings
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushInline()
            textTag = name

        // Paragraph-ish boundaries
        case "p", "div", "section", "article", "main", "header", "footer", "address", "dd", "figure", "figcaption", "summary", "details":
            if !isInTableCell { flushInline() }
            if name == "figcaption" { isCapturingCaption = true }

        case "dt":
            flushInline()
            boldDepth += 1

        case "hr":
            flushInline()
            top.blocks.append(ArticleBlock(.separator))

        // Grouping containers
        case "blockquote", "aside":
            push(name)

        case "ul", "ol":
            push(name)
            top.listIsOrdered = (name == "ol")
            top.listStart = attributes["start"].flatMap(Int.init) ?? 1

        case "li":
            if top.tag == "li" { closeTop() }
            push("li")

        case "table":
            push("table")

        case "caption":
            isCapturingCite = true

        case "tr":
            flushInline()
            if let table = enclosingTable() { finishRow(in: table) }

        case "td", "th":
            flushInline()
            isInTableCell = true
            if name == "th", let table = enclosingTable() { table.rowIsHeader = true }
            if name == "th" { boldDepth += 1 }

        case "pre":
            flushInline()
            isInPre = true
            preBuffer = ""
            preLanguage = Self.language(from: attributes)

        // Media
        case "img":
            appendImage(attributes)

        case "picture":
            pendingPictureSource = nil

        case "source":
            if let url = Self.mediaURL(from: attributes, baseURL: baseURL) {
                if pendingVideo != nil || pendingAudio != nil {
                    // Prefer a container AVFoundation can actually open over, say, WebM.
                    guard let existing = pendingSourceURL else {
                        pendingSourceURL = url
                        break
                    }
                    let candidateIsPlayable = Self.isNativelyPlayable(url: url, mimeType: attributes["type"])
                    let existingIsPlayable = Self.isNativelyPlayable(url: existing, mimeType: nil)
                    if candidateIsPlayable, !existingIsPlayable { pendingSourceURL = url }
                } else {
                    pendingPictureSource = url
                }
            }

        case "video":
            flushInline()
            let poster = attributes["poster"].flatMap { URL.resolving($0, relativeTo: baseURL) }
            let source = Self.mediaURL(from: attributes, baseURL: baseURL)
            pendingSourceURL = source
            pendingVideo = VideoMedia(url: source ?? URL(string: "about:blank")!, posterURL: poster, mimeType: attributes["type"], caption: nil, title: attributes["title"])

        case "audio":
            flushInline()
            let source = Self.mediaURL(from: attributes, baseURL: baseURL)
            pendingSourceURL = source
            pendingAudio = AudioMedia(url: source ?? URL(string: "about:blank")!, title: attributes["title"], mimeType: attributes["type"])

        case "iframe", "embed":
            flushInline()
            appendEmbed(attributes, urlKey: "src")

        case "object":
            flushInline()
            appendEmbed(attributes, urlKey: "data")

        default:
            break
        }
    }

    // MARK: End tags

    private func endTag(_ name: String) {
        if isInPre {
            if name == "pre" {
                isInPre = false
                let text = Self.trimmingBlankEdges(preBuffer)
                if !text.isEmpty {
                    top.blocks.append(ArticleBlock(.code(CodeBlock(text: text, language: preLanguage))))
                }
                preBuffer = ""
                preLanguage = nil
            }
            return
        }

        switch name {
        case "strong", "b": boldDepth = max(0, boldDepth - 1)
        case "em", "i", "var", "dfn": italicDepth = max(0, italicDepth - 1)
        case "code", "kbd", "samp", "tt": codeDepth = max(0, codeDepth - 1)
        case "del", "s", "strike": strikeDepth = max(0, strikeDepth - 1)
        case "sup": superscriptDepth = max(0, superscriptDepth - 1)
        case "sub": subscriptDepth = max(0, subscriptDepth - 1)

        case "cite":
            if isInsideCite {
                isCapturingCite = true
                flushInline()
                isCapturingCite = false
                isInsideCite = false
            } else {
                italicDepth = max(0, italicDepth - 1)
            }

        case "caption":
            flushInline()
            isCapturingCite = false

        case "a":
            if !linkStack.isEmpty { linkStack.removeLast() }

        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushInline()
            textTag = "p"

        case "dt":
            flushInline()
            boldDepth = max(0, boldDepth - 1)

        case "figcaption":
            attachCaption(Self.trimming(inline))
            inline = AttributedString()
            isCapturingCaption = false

        case "p", "div", "section", "article", "main", "header", "footer", "address", "dd", "figure", "summary", "details":
            if !isInTableCell { flushInline() }

        case "blockquote", "aside", "ul", "ol", "li", "table":
            closeContainer(name)

        case "tr":
            flushInline()
            if let table = enclosingTable() { finishRow(in: table) }

        case "td", "th":
            if name == "th" { boldDepth = max(0, boldDepth - 1) }
            isInTableCell = false
            let cell = Self.trimming(inline)
            inline = AttributedString()
            if let table = enclosingTable() { table.currentRow.append(cell) }

        case "video":
            if var video = pendingVideo {
                if let source = pendingSourceURL { video.url = source }
                if video.url.scheme != nil, video.url.absoluteString != "about:blank" {
                    top.blocks.append(ArticleBlock(.video(video)))
                }
            }
            pendingVideo = nil
            pendingSourceURL = nil

        case "audio":
            if var audio = pendingAudio {
                if let source = pendingSourceURL { audio.url = source }
                if audio.url.scheme != nil, audio.url.absoluteString != "about:blank" {
                    top.blocks.append(ArticleBlock(.audio(audio)))
                }
            }
            pendingAudio = nil
            pendingSourceURL = nil

        case "picture":
            pendingPictureSource = nil

        default:
            break
        }
    }

    private func enclosingTable() -> Container? {
        stack.last(where: { $0.tag == "table" })
    }

    // MARK: Media helpers

    private func appendImage(_ attributes: [String: String]) {
        guard let url = Self.mediaURL(from: attributes, baseURL: baseURL) ?? pendingPictureSource else { return }
        guard !suppressedImageURLs.contains(url) else { return }

        var image = ImageMedia(url: url)
        image.altText = attributes["alt"]?.squeezedWhitespace.nilIfEmpty
        image.pixelWidth = attributes["width"].flatMap { Int($0.filter(\.isNumber)) }
        image.pixelHeight = attributes["height"].flatMap { Int($0.filter(\.isNumber)) }
        image.linkURL = currentLink
        guard !image.isProbablyDecorative else { return }

        if let title = attributes["title"]?.squeezedWhitespace.nilIfEmpty {
            image.caption = AttributedString(title)
        }

        flushInline()
        top.blocks.append(ArticleBlock(.image(image)))
        pendingPictureSource = nil
    }

    private func appendEmbed(_ attributes: [String: String], urlKey: String) {
        guard let raw = attributes[urlKey], let url = URL.resolving(raw, relativeTo: baseURL) else { return }
        guard url.scheme == "http" || url.scheme == "https" else { return }

        let width = attributes["width"].flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
        let height = attributes["height"].flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
        var ratio: Double?
        if let width, let height, width > 0, height > 0 { ratio = width / height }

        // A direct media file inside an <iframe> is better served by AVKit.
        switch MediaKind.inferred(mimeType: attributes["type"], url: url) {
        case .video:
            top.blocks.append(ArticleBlock(.video(VideoMedia(url: url, posterURL: nil, mimeType: attributes["type"], caption: nil, title: attributes["title"]))))
        case .audio:
            top.blocks.append(ArticleBlock(.audio(AudioMedia(url: url, title: attributes["title"], mimeType: attributes["type"]))))
        default:
            top.blocks.append(ArticleBlock(.embed(EmbedMedia(url: url, title: attributes["title"], aspectRatio: ratio))))
        }
    }

    private func attachCaption(_ caption: AttributedString) {
        guard !String(caption.characters).trimmed.isEmpty else { return }

        // Walk back to the most recent piece of media and label it.
        for index in top.blocks.indices.reversed() {
            switch top.blocks[index].kind {
            case .image(var image) where image.caption == nil:
                image.caption = caption
                top.blocks[index].kind = .image(image)
                return
            case .video(var video) where video.caption == nil:
                video.caption = caption
                top.blocks[index].kind = .video(video)
                return
            case .embed(var embed) where embed.caption == nil:
                embed.caption = caption
                top.blocks[index].kind = .embed(embed)
                return
            case .gallery, .audio, .image, .video, .embed:
                break
            default:
                // Ran past the media: keep the caption as ordinary prose.
                top.blocks.append(ArticleBlock(.paragraph(caption)))
                return
            }
        }
        top.blocks.append(ArticleBlock(.paragraph(caption)))
    }
}

// MARK: - Static helpers

private extension Builder {

    /// Lazy-loading attributes, `srcset`, then plain `src`.
    static func mediaURL(from attributes: [String: String], baseURL: URL?) -> URL? {
        let directKeys = ["src", "data-src", "data-original", "data-lazy-src", "data-srcset", "data-url", "href"]
        if let srcset = attributes["srcset"] ?? attributes["data-srcset"],
           let best = largestCandidate(inSrcset: srcset, baseURL: baseURL) {
            return best
        }
        for key in directKeys {
            guard let value = attributes[key]?.trimmed, !value.isEmpty else { continue }
            if value.contains(",") && value.contains(" ") , let best = largestCandidate(inSrcset: value, baseURL: baseURL) {
                return best
            }
            if let url = URL.resolving(value, relativeTo: baseURL), url.scheme != "data" {
                return url
            }
        }
        return nil
    }

    /// `foo-320.jpg 320w, foo-1024.jpg 1024w` — take the widest.
    static func largestCandidate(inSrcset srcset: String, baseURL: URL?) -> URL? {
        var best: (url: URL, weight: Double)?
        for candidate in srcsetCandidates(srcset) {
            guard let url = URL.resolving(candidate.url, relativeTo: baseURL), url.scheme != "data" else { continue }
            var weight = 1.0
            if !candidate.descriptor.isEmpty {
                weight = Double(candidate.descriptor.filter { $0.isNumber || $0 == "." }) ?? 1
                if candidate.descriptor.hasSuffix("x") { weight *= 1000 }
            }
            if best == nil || weight > best!.weight { best = (url, weight) }
        }
        return best?.url
    }

    /// Split a srcset into its candidates, the way HTML says to.
    ///
    /// Not `split(separator: ",")`. A candidate's URL is simply everything up
    /// to the next space, and it is allowed to contain commas — Cloudflare's
    /// image resizing keeps its options in the path, so every picture on a
    /// site behind it arrives as
    /// `/cdn-cgi/image/format=auto,width=1200,metadata=none/photo.jpg`.
    /// Splitting on commas reduced each of those to rubble and then picked
    /// whichever fragment had ended up next to the width, which fetched a 404.
    ///
    /// A comma only ends a candidate where it trails the URL — the
    /// descriptor-less `a.jpg, b.jpg` form — or closes the descriptor.
    static func srcsetCandidates(_ srcset: String) -> [(url: String, descriptor: String)] {
        var candidates: [(url: String, descriptor: String)] = []
        let characters = Array(srcset)
        var index = 0

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
                index += 1
            }
            guard index < characters.count else { break }

            let urlStart = index
            while index < characters.count, !characters[index].isWhitespace { index += 1 }
            var url = String(characters[urlStart..<index])

            var descriptor = ""
            if url.hasSuffix(",") {
                while url.hasSuffix(",") { url.removeLast() }
            } else {
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                let descriptorStart = index
                while index < characters.count, characters[index] != "," { index += 1 }
                descriptor = String(characters[descriptorStart..<index]).trimmed
                if index < characters.count { index += 1 }
            }

            if !url.isEmpty { candidates.append((url, descriptor)) }
        }
        return candidates
    }

    static func isNativelyPlayable(url: URL, mimeType: String?) -> Bool {
        let playable: Set<String> = ["mp4", "m4v", "mov", "m3u8", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf"]
        if playable.contains(url.pathExtension.lowercased()) { return true }
        guard let mimeType = mimeType?.lowercased() else { return false }
        return mimeType.contains("mp4") || mimeType.contains("mpeg") || mimeType.contains("quicktime")
            || mimeType.contains("x-m4a") || mimeType.contains("aac") || mimeType.contains("mpegurl")
    }

    static func language(from attributes: [String: String]) -> String? {
        guard let classes = attributes["class"]?.lowercased() else { return attributes["data-language"] }
        for token in classes.split(separator: " ") {
            if token.hasPrefix("language-") { return String(token.dropFirst("language-".count)) }
            if token.hasPrefix("lang-") { return String(token.dropFirst("lang-".count)) }
            if token.hasPrefix("brush:") { return String(token.dropFirst("brush:".count)) }
        }
        return attributes["data-language"]
    }

    static func collapsingWhitespace(_ input: String) -> String {
        var output = ""
        output.reserveCapacity(input.count)
        var lastWasSpace = false
        for character in input {
            if character.isWhitespace {
                // Newlines in source markup are whitespace, not line breaks; only <br> breaks a line.
                if !lastWasSpace { output.append(" ") }
                lastWasSpace = true
            } else {
                output.append(character)
                lastWasSpace = false
            }
        }
        return output
    }

    static func trimming(_ input: AttributedString) -> AttributedString {
        var result = input
        while let first = result.characters.first, first.isWhitespace {
            result.removeSubrange(result.startIndex..<result.index(afterCharacter: result.startIndex))
        }
        while let last = result.characters.last, last.isWhitespace {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex)
        }
        return result
    }

    static func trimmingBlankEdges(_ input: String) -> String {
        var lines = input.components(separatedBy: "\n")
        while let first = lines.first, first.trimmed.isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmed.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// `<br><br>` is how half the web writes a paragraph break.
    static func splittingOnBlankLines(_ input: AttributedString) -> [AttributedString] {
        let characters = input.characters
        guard String(characters).contains("\n\n") else { return [input] }

        var paragraphs: [AttributedString] = []
        var current = input
        while let range = current.range(of: "\n\n") {
            let head = AttributedString(current[current.startIndex..<range.lowerBound])
            let trimmedHead = trimming(head)
            if !String(trimmedHead.characters).trimmed.isEmpty { paragraphs.append(trimmedHead) }
            current = AttributedString(current[range.upperBound...])
        }
        let tail = trimming(current)
        if !String(tail.characters).trimmed.isEmpty { paragraphs.append(tail) }
        return paragraphs.isEmpty ? [input] : paragraphs
    }

    static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]

    static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎"
    ]

    /// Footnote markers look right only when they're actually raised.
    static func superscripted(_ text: String) -> String {
        guard text.allSatisfy({ superscriptMap[$0] != nil || $0.isWhitespace }) else { return text }
        return String(text.map { superscriptMap[$0] ?? $0 })
    }

    static func subscripted(_ text: String) -> String {
        guard text.allSatisfy({ subscriptMap[$0] != nil || $0.isWhitespace }) else { return text }
        return String(text.map { subscriptMap[$0] ?? $0 })
    }
}
