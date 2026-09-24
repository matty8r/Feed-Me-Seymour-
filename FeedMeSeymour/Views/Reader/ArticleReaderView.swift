//
//  ArticleReaderView.swift
//  Feed Me, Seymour!
//
//  The reader takes over the pane. Everything in it is native SwiftUI, so the
//  type is real type, the media has real controls, and the text is selectable,
//  searchable and speakable.
//

import SwiftUI
import SwiftData

struct ArticleReaderView: View {

    let article: Article

    @Environment(AppModel.self) private var model
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var rendered = RenderedArticle(leadImage: nil, blocks: [])
    @State private var lightboxImage: ImageMedia?
    @State private var scrollProgress: Double = 0
    @FocusState private var isFocused: Bool

    private var typography: Typography {
        Typography(settings: settings, dynamicTypeSize: dynamicTypeSize)
    }

    private var speech: SpeechReader { .shared }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            progressBar
            Divider().opacity(0.35)
            scrollingBody
            #if os(iOS)
            // Where the search field used to sit. On the Mac these two stay in
            // the top bar, within easy reach of the pointer and of J and K.
            articleNavigationBar
            #endif
        }
        .background(palette.paper)
        .environment(\.typography, typography)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            render()
        }
        .onChange(of: article.persistentModelID) { _, _ in
            scrollProgress = 0
            render()
        }
        .onChange(of: article.contentHTML) { _, _ in render() }
        // Arrows are left to the scroll view here: inside an article they
        // mean "move down the page". J and K are what walk the timeline.
        .onKeyPress(.escape) {
            model.collapse()
            return .handled
        }
        .onKeyPress(.space) {
            model.collapse()
            return .handled
        }
        .onKeyPress(characters: .alphanumerics) { press in
            switch press.characters {
            case "j": model.goToNext(); return .handled
            case "k": model.goToPrevious(); return .handled
            case "s": toggleStar(); return .handled
            case "l": toggleReadingAloud(); return .handled
            default: return .ignored
            }
        }
        .imageViewer(item: $lightboxImage)
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                model.collapse()
            } label: {
                Label("Close Article", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .closeGlyph()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to the timeline")

            if let feed = article.feed {
                HStack(spacing: 7) {
                    FeedIconView(feed: feed, size: 16)
                    Text(feed.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(palette.secondaryInk)
                .padding(.leading, 2)
            }

            Spacer(minLength: 8)

            // Four actions earn a place in the bar: where you are going, and
            // what you do with the article once you're there. Everything else
            // is one tap away under the ellipsis.
            HStack(spacing: 0) {
                #if os(macOS)
                Button { model.goToPrevious() } label: {
                    Image(systemName: "chevron.up").barGlyph()
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoToPrevious)
                .help("Previous Article")

                Button { model.goToNext() } label: {
                    Image(systemName: "chevron.down").barGlyph()
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoToNext)
                .help("Next Article")

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 6)
                #endif

                StarButton(isStarred: article.isStarred, size: BarGlyph.size, idleTint: \.ink) {
                    toggleStar()
                }
                .frame(width: BarGlyph.hit.width, height: BarGlyph.hit.height)

                if let url = article.url {
                    ShareLink(item: url, subject: Text(article.displayTitle), message: shareMessage) {
                        Image(systemName: "square.and.arrow.up").barGlyph()
                    }
                    .buttonStyle(.plain)
                    .help("Share Article")
                }

                overflowMenu
            }
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.paper)
    }

    private var overflowMenu: some View {
        Menu {
            Button(speech.isReading(article) ? "Stop Reading Aloud" : "Read Aloud",
                   systemImage: speech.isReading(article) ? "speaker.slash" : "speaker.wave.2") {
                toggleReadingAloud()
            }

            Menu("Text", systemImage: "textformat") {
                TypographyMenuItems()
            }

            Divider()

            Button(article.isRead ? "Mark as Unread" : "Mark as Read",
                   systemImage: article.isRead ? "circle" : "checkmark.circle") {
                article.setRead(!article.isRead)
                try? context.save()
            }

            if let url = article.url {
                Divider()
                Button("Open in Browser", systemImage: "safari") { openURL(url) }
                Button("Copy Link", systemImage: "link") { Platform.copyToPasteboard(url.absoluteString) }
            }
        } label: {
            Image(systemName: "ellipsis").barGlyph()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private var shareMessage: Text? {
        guard let summary = article.plainSummary.nilIfEmpty else { return nil }
        return Text(summary.truncated(to: 180))
    }

    #if os(iOS)
    /// Moving between articles, put where a thumb already is. The same two
    /// moves as pulling past either end of the article — that gesture is
    /// quicker once you know it, and this is how you find out it exists.
    private var articleNavigationBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                navigationButton(
                    title: "Previous",
                    symbol: "chevron.left",
                    isEnabled: model.canGoToPrevious,
                    alignment: .leading
                ) { model.goToPrevious() }

                navigationButton(
                    title: "Next",
                    symbol: "chevron.right",
                    isEnabled: model.canGoToNext,
                    alignment: .trailing
                ) { model.goToNext() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(palette.paper)
    }

    private func navigationButton(title: String,
                                  symbol: String,
                                  isEnabled: Bool,
                                  alignment: HorizontalAlignment,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if alignment == .leading {
                    Image(systemName: symbol)
                    Text(title)
                } else {
                    Text(title)
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: BarGlyph.size, weight: BarGlyph.weight))
            .foregroundStyle(isEnabled ? palette.ink : palette.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .frame(height: BarGlyph.hit.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(alignment == .leading ? "Previous Article" : "Next Article")
    }
    #endif

    private var progressBar: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(palette.accent)
                .frame(width: proxy.size.width * scrollProgress)
                .animation(.linear(duration: 0.08), value: scrollProgress)
        }
        .frame(height: 2)
        .background(palette.rule.opacity(0.4))
        .accessibilityHidden(true)
    }

    // MARK: - Body

    private var scrollingBody: some View {
        renderedBody
            // Keyed by article, so changing article replaces this subtree
            // instead of mutating it. Mutating it in place is what made the
            // text shuffle around as blocks of different heights swapped
            // between one article and the next; replacing it lets the old one
            // dissolve into the new.
            .id(article.persistentModelID)
            .transition(.opacity)
            // Scoped to the body. On the whole view it dragged the toolbar and
            // the progress bar into every article change too.
            .animation(.easeInOut(duration: 0.18), value: article.persistentModelID)
    }

    private var renderedBody: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 1).id("reader.top")

                    ArticleHeaderView(article: article, leadImage: rendered.leadImage) { image in
                        lightboxImage = image
                    }

                    if rendered.blocks.isEmpty {
                        emptyBody
                    } else {
                        ArticleBodyView(blocks: rendered.blocks, article: article) { image in
                            lightboxImage = image
                        }
                    }

                    ArticleFooterView(article: article)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 26)
            }
            .scrollIndicators(.automatic)
            .textSelection(.enabled)
            .background(palette.paper)
            .onScrollGeometryChange(for: Double.self) { geometry in
                // Reach 100% when the last line of the article does, not when
                // the very bottom of the scroll view does.
                let scrollable = max(geometry.contentSize.height - geometry.containerSize.height, 1)
                return min(max(geometry.contentOffset.y / scrollable, 0), 1)
            } action: { _, progress in
                scrollProgress = progress
            }
            .overscrollArticleNavigation(
                next: overscrollDestination(for: model.nextArticleID),
                previous: overscrollDestination(for: model.previousArticleID),
                goToNext: { model.goToNext() },
                goToPrevious: { model.goToPrevious() }
            )
            .onChange(of: article.persistentModelID) { _, _ in
                scroller.scrollTo("reader.top", anchor: .top)
            }
            .onChange(of: speech.currentBlockID) { _, blockID in
                // Keep the spoken paragraph on screen, but only for the article
                // actually being read.
                guard let blockID, speech.articleID == article.persistentModelID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    scroller.scrollTo(blockID, anchor: .center)
                }
            }
        }
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(article.isPlaceholder
                 ? "This favorite came from another device. Its text will appear the next time this feed is refreshed."
                 : "This entry is only a headline.")
                .font(typography.body)
                .foregroundStyle(palette.secondaryInk)
            if let url = article.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Read at \(url.prettyHost)", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: typography.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Actions

    /// The title the pull indicator promises. Nil at either end of the
    /// timeline, which is what hides the indicator entirely.
    private func overscrollDestination(for id: PersistentIdentifier?) -> OverscrollDestination? {
        guard let article = context.article(with: id) else { return nil }
        return OverscrollDestination(title: article.displayTitle)
    }

    private func render() {
        rendered = ArticleRenderer.shared.render(article)
        prepareNeighbours()
        if settings.marksReadOnOpen, !article.isRead {
            article.setRead(true)
            try? context.save()
        }
    }

    /// Render what's on either side while this article is being read, so
    /// moving on doesn't have to parse anything.
    private func prepareNeighbours() {
        for id in [model.nextArticleID, model.previousArticleID] {
            if let neighbour = context.article(with: id) {
                ArticleRenderer.shared.prepare(neighbour)
            }
        }
    }

    private func toggleStar() {
        article.toggleStar()
        try? context.save()
    }

    private func toggleReadingAloud() {
        if speech.isReading(article) {
            speech.stop()
        } else {
            // The render cache means this costs nothing the second time.
            speech.start(article: article, rendered: ArticleRenderer.shared.render(article), settings: settings)
        }
    }
}
