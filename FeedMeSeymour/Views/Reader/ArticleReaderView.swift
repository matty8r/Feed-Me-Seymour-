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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            progressBar
            Divider().opacity(0.35)
            scrollingBody
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
            default: return .ignored
            }
        }
        .imageViewer(item: $lightboxImage)
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.collapse()
            } label: {
                Label("Back to Timeline", systemImage: Platform.isMac ? "chevron.left" : "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
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
            }

            Spacer(minLength: 8)

            Button { model.goToPrevious() } label: {
                Image(systemName: "chevron.up").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoToPrevious)
            .help("Previous Article")

            Button { model.goToNext() } label: {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoToNext)
            .help("Next Article")

            Divider().frame(height: 16)

            StarButton(isStarred: article.isStarred, size: 16) { toggleStar() }

            TypographyMenu()

            if let url = article.url {
                Menu {
                    Button("Open in Browser", systemImage: "safari") { openURL(url) }
                    Button("Copy Link", systemImage: "link") { Platform.copyToPasteboard(url.absoluteString) }
                    Button(article.isRead ? "Mark as Unread" : "Mark as Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                        article.isRead.toggle()
                        try? context.save()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 15))
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")

                ShareLink(item: url, subject: Text(article.displayTitle), message: shareMessage) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Share Article")
            }
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.paper)
    }

    private var shareMessage: Text? {
        guard let summary = article.plainSummary.nilIfEmpty else { return nil }
        return Text(summary.truncated(to: 180))
    }

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
            .onChange(of: article.persistentModelID) { _, _ in
                scroller.scrollTo("reader.top", anchor: .top)
            }
        }
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This entry is only a headline.")
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

    private func render() {
        rendered = ArticleRenderer.shared.render(article)
        if settings.marksReadOnOpen, !article.isRead {
            article.isRead = true
            try? context.save()
        }
    }

    private func toggleStar() {
        article.toggleStar()
        try? context.save()
    }
}
