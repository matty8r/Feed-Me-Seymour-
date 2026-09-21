//
//  ArticleBodyView.swift
//  Feed Me, Seymour!
//
//  Renders parsed blocks as native views. Nothing here is a web view, so every
//  paragraph respects the reader's type settings and every piece of media gets
//  the system's own controls.
//

import SwiftUI

struct ArticleBodyView: View {

    let blocks: [ArticleBlock]
    let article: Article
    var onTapImage: (ImageMedia) -> Void

    @Environment(\.typography) private var typography

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                BlockView(block: block, article: article, onTapImage: onTapImage)
                    .frame(
                        maxWidth: block.prefersFullWidth ? typography.mediaWidth : typography.columnWidth,
                        alignment: .leading
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .id(block.id)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - One block

struct BlockView: View {

    let block: ArticleBlock
    let article: Article
    var onTapImage: (ImageMedia) -> Void
    var isNested = false

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        content
            .padding(.top, topPadding)
    }

    private var topPadding: Double {
        switch block.kind {
        case .paragraph: typography.paragraphSpacing
        case .heading(let level, _): typography.headingTopPadding(level: level)
        case .separator: typography.blockSpacing
        case .quote, .list, .code, .table: typography.blockSpacing
        case .image, .gallery, .video, .audio, .embed: typography.blockSpacing
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .paragraph(let text):
            ParagraphView(text: text, blockID: block.id)

        case .heading(let level, let text):
            Text(text)
                .font(typography.heading(level: level))
                .lineSpacing(typography.headingLineSpacing)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

        case .quote(let blocks, let attribution):
            QuoteBlockView(blocks: blocks, attribution: attribution, article: article, onTapImage: onTapImage)

        case .list(let list):
            ListBlockView(list: list, article: article, onTapImage: onTapImage)

        case .code(let code):
            CodeBlockView(code: code)

        case .image(let image):
            if settings.showsImages {
                ImageBlockView(image: image, onTap: onTapImage)
            }

        case .gallery(let images):
            if settings.showsImages {
                GalleryBlockView(images: images, onTap: onTapImage)
            }

        case .video(let video):
            VideoBlockView(media: video)

        case .audio(let audio):
            AudioPlayerCard(media: audio, subtitle: article.feed?.displayTitle)

        case .embed(let embed):
            VStack(alignment: .leading, spacing: 8) {
                EmbedView(media: embed)
                if let caption = embed.caption {
                    CaptionView(text: caption)
                }
            }

        case .table(let table):
            TableBlockView(table: table)

        case .separator:
            Ornament()
        }
    }
}

/// A paragraph, plus the word being spoken when this is the block being read.
///
/// The guard short-circuits, so a paragraph that isn't currently being read
/// never touches `spokenRange` and therefore never re-renders on a word
/// boundary — only the one paragraph being spoken does.
struct ParagraphView: View {

    let text: AttributedString
    let blockID: UUID

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    private var speech: SpeechReader { .shared }

    var body: some View {
        Text(rendered)
            .font(typography.body)
            .lineSpacing(typography.bodyLineSpacing)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rendered: AttributedString {
        guard speech.currentBlockID == blockID, let range = speech.spokenRange else { return text }
        return text.highlightingCharacters(in: range, with: palette.accent.opacity(0.22))
    }
}

extension AttributedString {
    /// `range` is in characters, which is what the speech reader converts
    /// `NSRange` into — mixing UTF-16 offsets in here would misplace the
    /// highlight on any paragraph containing an emoji or a combining mark.
    func highlightingCharacters(in range: Range<Int>, with color: Color) -> AttributedString {
        let length = characters.count
        guard range.lowerBound >= 0, range.upperBound <= length, range.lowerBound < range.upperBound else {
            return self
        }
        var copy = self
        let start = copy.index(copy.startIndex, offsetByCharacters: range.lowerBound)
        let end = copy.index(copy.startIndex, offsetByCharacters: range.upperBound)
        copy[start..<end].backgroundColor = color
        return copy
    }
}

// MARK: - Quote

struct QuoteBlockView: View {
    let blocks: [ArticleBlock]
    let attribution: AttributedString?
    let article: Article
    var onTapImage: (ImageMedia) -> Void

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(palette.quoteBar)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    quoted(block, isFirst: index == 0)
                }

                if let attribution {
                    Text(attribution)
                        .font(typography.caption)
                        .foregroundStyle(palette.tertiaryInk)
                        .padding(.top, 10)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func quoted(_ block: ArticleBlock, isFirst: Bool) -> some View {
        switch block.kind {
        case .paragraph(let text):
            Text(text)
                .font(typography.quote)
                .italic()
                .lineSpacing(typography.quoteLineSpacing)
                .foregroundStyle(palette.ink.opacity(0.88))
                .tint(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isFirst ? 0 : typography.paragraphSpacing)
        default:
            BlockView(block: block, article: article, onTapImage: onTapImage, isNested: true)
        }
    }
}

// MARK: - Lists

struct ListBlockView: View {
    let list: ListBlock
    let article: Article
    var onTapImage: (ImageMedia) -> Void

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: typography.paragraphSpacing * 0.6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(for: index)
                        .frame(minWidth: list.isOrdered ? 24 : 12, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.enumerated()), id: \.element.id) { blockIndex, block in
                            itemBlock(block, isFirst: blockIndex == 0)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func marker(for index: Int) -> some View {
        if list.isOrdered {
            Text("\(list.start + index).")
                .font(typography.body)
                .monospacedDigit()
                .foregroundStyle(palette.tertiaryInk)
        } else {
            Text("•")
                .font(typography.body)
                .foregroundStyle(palette.accent)
        }
    }

    @ViewBuilder
    private func itemBlock(_ block: ArticleBlock, isFirst: Bool) -> some View {
        switch block.kind {
        case .paragraph(let text):
            Text(text)
                .font(typography.body)
                .lineSpacing(typography.bodyLineSpacing)
                .foregroundStyle(palette.ink)
                .tint(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isFirst ? 0 : typography.paragraphSpacing * 0.5)
        default:
            BlockView(block: block, article: article, onTapImage: onTapImage, isNested: true)
        }
    }
}

// MARK: - Code

struct CodeBlockView: View {
    let code: CodeBlock

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = code.language?.nilIfEmpty {
                HStack {
                    Text(language.uppercased())
                        .font(typography.label)
                        .tracking(typography.labelTracking)
                        .foregroundStyle(palette.tertiaryInk)
                    Spacer()
                    copyButton
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.text)
                    .font(typography.code)
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.codeBackground))
        .overlay(alignment: .topTrailing) {
            if code.language?.nilIfEmpty == nil {
                copyButton.padding(10)
            }
        }
    }

    private var copyButton: some View {
        Button {
            Platform.copyToPasteboard(code.text)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.tertiaryInk)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("Copy Code")
    }
}

// MARK: - Images

struct ImageBlockView: View {
    let image: ImageMedia
    var onTap: (ImageMedia) -> Void

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onTap(image) } label: {
                RemoteImage(url: image.url, contentMode: .fit, aspectRatio: image.aspectRatio, cornerRadius: 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(image.altText ?? "Image")
            .contextMenu {
                ShareLink(item: image.url)
                Button("Copy Image Address", systemImage: "link") {
                    Platform.copyToPasteboard(image.url.absoluteString)
                }
                if let link = image.linkURL {
                    Link(destination: link) { Label("Open Link", systemImage: "arrow.up.forward") }
                }
            }

            if let caption = image.caption {
                CaptionView(text: caption)
            }
        }
    }
}

struct GalleryBlockView: View {
    let images: [ImageMedia]
    var onTap: (ImageMedia) -> Void

    @Environment(\.typography) private var typography

    private var columns: [GridItem] {
        let count = images.count <= 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(images) { image in
                Button { onTap(image) } label: {
                    RemoteImage(url: image.url, contentMode: .fill, aspectRatio: 1, cornerRadius: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(image.altText ?? "Image")
            }
        }
    }
}

// MARK: - Video

struct VideoBlockView: View {
    let media: VideoMedia

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if isPlaying {
                    VideoSurface(url: media.url)
                } else {
                    poster
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contextMenu {
                ShareLink(item: media.url)
                Button("Copy Link", systemImage: "link") { Platform.copyToPasteboard(media.url.absoluteString) }
            }

            if let caption = media.caption {
                CaptionView(text: caption)
            }
        }
    }

    private var poster: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isPlaying = true }
        } label: {
            ZStack {
                palette.codeBackground
                if let posterURL = media.posterURL {
                    RemoteImage(url: posterURL, contentMode: .fill, showsProgress: false)
                        .overlay(Color.black.opacity(0.2))
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .shadow(color: .black.opacity(0.3), radius: 10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.title ?? "Play video")
    }
}

/// Creates the `AVPlayer` once, when the reader actually asks for it.
private struct VideoSurface: View {
    let url: URL
    @StateObject private var box: VideoPlayerBox

    init(url: URL) {
        self.url = url
        _box = StateObject(wrappedValue: VideoPlayerBox(url: url))
    }

    var body: some View {
        NativeVideoPlayer(player: box.player)
    }
}

// MARK: - Tables

struct TableBlockView: View {
    let table: TableBlock

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if !table.headers.isEmpty {
                        row(table.headers, isHeader: true)
                        Hairline()
                    }
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, cells in
                        row(cells, isHeader: false)
                            .background(index.isMultiple(of: 2) ? Color.clear : palette.codeBackground.opacity(0.6))
                    }
                }
                .frame(minWidth: 0)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.codeBackground.opacity(0.35)))

            if let caption = table.caption {
                CaptionView(text: caption)
            }
        }
    }

    private func row(_ cells: [AttributedString], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(typography.tableCell)
                    .fontWeight(isHeader ? .semibold : .regular)
                    .foregroundStyle(isHeader ? palette.ink : palette.secondaryInk)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 96, maxWidth: 280, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
    }
}

// MARK: - Small parts

struct CaptionView: View {
    let text: AttributedString

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(typography.caption)
            .lineSpacing(typography.captionLineSpacing)
            .foregroundStyle(palette.secondaryInk)
            .tint(palette.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section break that looks composed rather than like a horizontal rule.
struct Ornament: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(palette.tertiaryInk)
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
