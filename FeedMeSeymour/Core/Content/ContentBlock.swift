//
//  ContentBlock.swift
//  Feed Me, Seymour!
//
//  The article, after HTML, as a flat list of things SwiftUI knows how to draw
//  beautifully. No web view, so every paragraph honours Dynamic Type and every
//  piece of media gets a real AVKit control.
//

import Foundation

// MARK: - Media

struct ImageMedia: Hashable, Identifiable, Sendable {
    var id: URL { url }
    var url: URL
    var altText: String? = nil
    var caption: AttributedString? = nil
    var linkURL: URL? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil

    /// Used to reserve the right amount of space before the bytes arrive.
    var aspectRatio: Double? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var isAnimated: Bool {
        url.pathExtension.lowercased() == "gif"
    }

    /// Tracking pixels and spacer GIFs shouldn't earn a full-width figure.
    var isProbablyDecorative: Bool {
        if let pixelWidth, pixelWidth <= 4 { return true }
        if let pixelHeight, pixelHeight <= 4 { return true }
        let path = url.path.lowercased()
        return path.contains("/pixel") || path.contains("spacer.gif") || path.contains("blank.gif")
            || url.host()?.contains("feedburner") == true
            || url.host()?.contains("feedsportal") == true
            || url.host()?.contains("pixel.wp.com") == true
    }
}

struct VideoMedia: Hashable, Identifiable, Sendable {
    var id: URL { url }
    var url: URL
    var posterURL: URL? = nil
    var mimeType: String? = nil
    var caption: AttributedString? = nil
    var title: String? = nil
}

struct AudioMedia: Hashable, Identifiable, Sendable {
    var id: URL { url }
    var url: URL
    var title: String? = nil
    var mimeType: String? = nil
    var artworkURL: URL? = nil
    var duration: TimeInterval? = nil
}

enum EmbedProvider: String, Hashable, Sendable {
    case youTube, vimeo, spotify, appleMusic, appleTV, soundCloud, bandcamp, mastodon, blueSky, codepen, generic

    var displayName: String {
        switch self {
        case .youTube: "YouTube"
        case .vimeo: "Vimeo"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .appleTV: "Apple TV"
        case .soundCloud: "SoundCloud"
        case .bandcamp: "Bandcamp"
        case .mastodon: "Mastodon"
        case .blueSky: "Bluesky"
        case .codepen: "CodePen"
        case .generic: "Embedded media"
        }
    }

    var symbolName: String {
        switch self {
        case .youTube, .vimeo, .appleTV: "play.rectangle.fill"
        case .spotify, .appleMusic, .soundCloud, .bandcamp: "music.note"
        case .mastodon, .blueSky: "bubble.left.and.bubble.right.fill"
        case .codepen: "chevron.left.forwardslash.chevron.right"
        case .generic: "rectangle.on.rectangle"
        }
    }

    /// A sensible default shape so embeds don't jump around while loading.
    var defaultAspectRatio: Double {
        switch self {
        case .youTube, .vimeo, .appleTV, .codepen: 16.0 / 9.0
        case .spotify, .appleMusic, .soundCloud, .bandcamp: 16.0 / 9.0
        case .mastodon, .blueSky: 4.0 / 5.0
        case .generic: 16.0 / 9.0
        }
    }

    static func detect(_ url: URL) -> EmbedProvider {
        let host = (url.host() ?? "").lowercased()
        switch true {
        case host.contains("youtube.com"), host.contains("youtu.be"), host.contains("youtube-nocookie"):
            return .youTube
        case host.contains("vimeo.com"):
            return .vimeo
        case host.contains("spotify.com"):
            return .spotify
        case host.contains("music.apple.com"):
            return .appleMusic
        case host.contains("tv.apple.com"), host.contains("embed.podcasts.apple.com"):
            return .appleTV
        case host.contains("soundcloud.com"):
            return .soundCloud
        case host.contains("bandcamp.com"):
            return .bandcamp
        case host.contains("bsky.app"):
            return .blueSky
        case host.contains("codepen.io"):
            return .codepen
        case url.path.contains("/embed") && host.contains("mastodon"):
            return .mastodon
        default:
            return .generic
        }
    }
}

struct EmbedMedia: Hashable, Identifiable, Sendable {
    var id: URL { url }
    var url: URL
    var provider: EmbedProvider
    var title: String?
    var aspectRatio: Double
    var caption: AttributedString?

    init(url: URL, title: String? = nil, aspectRatio: Double? = nil, caption: AttributedString? = nil) {
        let provider = EmbedProvider.detect(url)
        self.url = url
        self.provider = provider
        self.title = title
        self.aspectRatio = aspectRatio ?? provider.defaultAspectRatio
        self.caption = caption
    }

    /// YouTube's own still, so a video embed has a face before it's tapped.
    var thumbnailURL: URL? {
        guard provider == .youTube, let identifier = youTubeID else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(identifier)/maxresdefault.jpg")
    }

    var youTubeID: String? {
        guard provider == .youTube else { return nil }
        if let host = url.host(), host.contains("youtu.be") {
            return url.lastPathComponent.nilIfEmpty
        }
        if url.path.contains("/embed/") || url.path.contains("/v/") {
            return url.lastPathComponent.nilIfEmpty
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value
    }

    /// Where "Open" should take the reader — the watchable page, not the iframe.
    var canonicalURL: URL {
        if provider == .youTube, let identifier = youTubeID,
           let watch = URL(string: "https://www.youtube.com/watch?v=\(identifier)") {
            return watch
        }
        return url
    }
}

// MARK: - Blocks

struct ListBlock: Hashable, Sendable {
    var isOrdered: Bool
    var start: Int = 1
    var items: [[ArticleBlock]]
}

struct TableBlock: Hashable, Sendable {
    var headers: [AttributedString]
    var rows: [[AttributedString]]
    var caption: AttributedString?

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }
}

struct CodeBlock: Hashable, Sendable {
    var text: String
    var language: String?
}

struct ArticleBlock: Identifiable, Hashable, Sendable {

    enum Kind: Hashable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        case quote(blocks: [ArticleBlock], attribution: AttributedString?)
        case list(ListBlock)
        case code(CodeBlock)
        case image(ImageMedia)
        case gallery([ImageMedia])
        case video(VideoMedia)
        case audio(AudioMedia)
        case embed(EmbedMedia)
        case table(TableBlock)
        case separator
    }

    let id: UUID
    var kind: Kind

    init(_ kind: Kind, id: UUID = UUID()) {
        self.kind = kind
        self.id = id
    }

    /// Wide media wants to break out of the text measure.
    var prefersFullWidth: Bool {
        switch kind {
        case .image, .gallery, .video, .embed, .table: true
        default: false
        }
    }

    var plainText: String {
        switch kind {
        case .paragraph(let text): String(text.characters)
        case .heading(_, let text): String(text.characters)
        case .quote(let blocks, let attribution):
            blocks.map(\.plainText).joined(separator: " ") + (attribution.map { " — " + String($0.characters) } ?? "")
        case .list(let list):
            list.items.map { $0.map(\.plainText).joined(separator: " ") }.joined(separator: "\n")
        case .code(let code): code.text
        case .image(let image): image.caption.map { String($0.characters) } ?? image.altText ?? ""
        case .gallery(let images): images.compactMap { $0.altText }.joined(separator: " ")
        case .video(let video): video.title ?? ""
        case .audio(let audio): audio.title ?? ""
        case .embed(let embed): embed.title ?? embed.provider.displayName
        case .table(let table):
            (table.headers + table.rows.flatMap { $0 }).map { String($0.characters) }.joined(separator: " ")
        case .separator: ""
        }
    }
}

extension Array where Element == ArticleBlock {
    var plainText: String {
        map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var wordCount: Int { plainText.wordCount }
}
