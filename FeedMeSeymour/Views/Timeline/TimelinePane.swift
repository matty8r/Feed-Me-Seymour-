//
//  TimelinePane.swift
//  Feed Me, Seymour!
//
//  The right-hand pane: one chronological list of everything subscribed, and
//  the reader that expands out of it to take the whole pane over.
//

import SwiftUI
import SwiftData
import Combine

struct TimelinePane: View {

    @Environment(AppModel.self) private var model
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var allArticles: [Article]

    @State private var hasSetInitialSelection = false
    @FocusState private var isListFocused: Bool

    // MARK: - Scoping

    private var scopedArticles: [Article] {
        var articles: [Article]

        switch model.selection {
        case .none, .some(.all):
            articles = allArticles
        case .some(.unread):
            articles = allArticles.filter { !$0.isRead }
        case .some(.starred):
            articles = allArticles.filter(\.isStarred)
        case .some(.feed(let id)):
            articles = allArticles.filter { $0.feed?.persistentModelID == id }
        }

        if settings.hidesReadArticles, model.selection != .starred {
            // Never hide the article the reader is looking at.
            articles = articles.filter { !$0.isRead || $0.persistentModelID == model.selectedArticleID }
        }

        let query = model.searchText.trimmed
        if !query.isEmpty {
            articles = articles.filter { article in
                article.title.localizedCaseInsensitiveContains(query)
                    || article.plainSummary.localizedCaseInsensitiveContains(query)
                    || (article.author ?? "").localizedCaseInsensitiveContains(query)
                    || (article.feed?.displayTitle ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return articles
    }

    private var scopeTitle: String {
        switch model.selection {
        case .none, .some(.all): "All Articles"
        case .some(.unread): "Unread"
        case .some(.starred): "Favorites"
        case .some(.feed(let id)): context.feed(with: id)?.displayTitle ?? "Feed"
        }
    }

    private var expandedArticle: Article? {
        context.article(with: model.expandedArticleID)
    }

    // MARK: - Body

    var body: some View {
        @Bindable var model = model
        let articles = scopedArticles

        ZStack {
            palette.canvas.ignoresSafeArea()

            // Taken out of the hierarchy rather than hidden behind the
            // reader. At zero opacity it was still there, and every row kept
            // rebuilding itself on each selection change — profiling a run
            // through articles with J showed the hot path was almost entirely
            // ArticleRowView, for rows nobody could see.
            if !model.isReaderExpanded {
                timelineList(articles)
                    // Searching belongs to the timeline, so it is attached to
                    // the timeline rather than to the pane. Hung on the pane it
                    // stayed in the toolbar behind the reader, offering to
                    // filter a list that was no longer on screen.
                    .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Articles")
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
            }

            if let article = expandedArticle {
                ArticleReaderView(article: article)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.975, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
                        )
                    )
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: model.expandedArticleID)
        .navigationTitle(model.isReaderExpanded ? "" : scopeTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(model.isReaderExpanded ? .hidden : .visible, for: .navigationBar)
        #endif
        .toolbar { if !model.isReaderExpanded { timelineToolbar(articles) } }
        .onChange(of: articles.map(\.persistentModelID)) { _, ids in
            model.visibleArticleIDs = ids
        }
        .onAppear { model.visibleArticleIDs = articles.map(\.persistentModelID) }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReader)) { _ in
            toggleReader()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFavorite)) { _ in
            guard let article = currentArticle else { return }
            article.toggleStar()
            try? context.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRead)) { _ in
            guard let article = currentArticle else { return }
            article.setRead(!article.isRead)
            try? context.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInBrowser)) { _ in
            if let url = currentArticle?.url { openURL(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readAloud)) { _ in
            guard let article = currentArticle else { return }
            let speech = SpeechReader.shared
            if speech.isReading(article) {
                speech.stop()
            } else {
                speech.start(article: article, rendered: ArticleRenderer.shared.render(article), settings: settings)
            }
        }
    }

    private var currentArticle: Article? {
        context.article(with: model.expandedArticleID ?? model.selectedArticleID)
    }

    /// Move the current article by one. With nothing selected yet, the first
    /// key press lands on the top of the list rather than doing nothing.
    @discardableResult
    private func moveSelection(_ step: Int, in articles: [Article]) -> KeyPress.Result {
        guard !articles.isEmpty else { return .handled }
        if model.selectedArticleID == nil {
            model.selectedArticleID = articles.first?.persistentModelID
            return .handled
        }
        if step > 0 { model.goToNext() } else { model.goToPrevious() }
        return .handled
    }

    // MARK: - List

    @ViewBuilder
    private func timelineList(_ articles: [Article]) -> some View {
        if articles.isEmpty {
            emptyState
        } else {
            ScrollViewReader { scroller in
                let selection = Binding(
                get: { model.selectedArticleID },
                set: { model.selectedArticleID = $0 }
            )

            List(selection: selection) {
                    ForEach(articles) { article in
                        ArticleRowView(
                            article: article,
                            showsFeedName: !isSingleFeedScope,
                            onOpen: { model.open(article) }
                        )
                        .tag(article.persistentModelID)
                        .id(article.persistentModelID)
                        .listRowBackground(rowBackground(for: article))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 10)
                .refreshable { await model.refresher.refreshAll(in: context) }
                // The list has to hold focus for any of the keys below to
                // reach it, and it has to take focus back when the reader
                // closes — the reader was holding it until a moment ago.
                .focusable()
                .focusEffectDisabled()
                .focused($isListFocused)
                .onAppear {
                    isListFocused = true
                    // The list is rebuilt when the reader closes, so put the
                    // article you were reading back under the eye.
                    if let id = model.selectedArticleID {
                        scroller.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: model.isReaderExpanded) { _, expanded in
                    if !expanded { isListFocused = true }
                }
                .onChange(of: model.selectedArticleID) { _, id in
                    // Keep the current article on screen when the keyboard,
                    // rather than the mouse, is what moved it.
                    //
                    // Only while the list is actually the thing on screen: it
                    // stays in the hierarchy behind the reader at zero opacity,
                    // and animating a scroll through it on every J/K press is
                    // work nobody can see.
                    guard let id, !model.isReaderExpanded else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        scroller.scrollTo(id, anchor: .center)
                    }
                }
                .onKeyPress(.upArrow) { moveSelection(-1, in: articles) }
                .onKeyPress(.downArrow) { moveSelection(1, in: articles) }
                .onKeyPress(.space) {
                    toggleReader()
                    return .handled
                }
                .onKeyPress(.return) {
                    toggleReader()
                    return .handled
                }
                .onKeyPress(characters: .alphanumerics) { press in
                    switch press.characters {
                    case "j":
                        return moveSelection(1, in: articles)
                    case "k":
                        return moveSelection(-1, in: articles)
                    case "s":
                        if let article = currentArticle { article.toggleStar(); try? context.save() }
                        return .handled
                    default:
                        return .ignored
                    }
                }
            }
        }
    }

    private var isSingleFeedScope: Bool {
        if case .some(.feed) = model.selection { return true }
        return false
    }

    private func rowBackground(for article: Article) -> some View {
        Group {
            if article.persistentModelID == model.selectedArticleID {
                palette.accent.opacity(0.12)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.trimmed.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyMessage)
            } actions: {
                Button("Refresh") {
                    Task { await model.refresher.refreshAll(in: context) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var emptyTitle: String {
        switch model.selection {
        case .some(.unread): "All Caught Up"
        case .some(.starred): "No Favorites"
        default: "Nothing Here Yet"
        }
    }

    private var emptySymbol: String {
        switch model.selection {
        case .some(.unread): "checkmark.circle"
        case .some(.starred): "star"
        default: "leaf"
        }
    }

    private var emptyMessage: String {
        switch model.selection {
        case .some(.unread): "You've read everything. Go outside."
        case .some(.starred): "Star an article and it will be waiting here."
        default: "Add a subscription, then pull to refresh."
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func timelineToolbar(_ articles: [Article]) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle("Hide Read Articles", isOn: Binding(
                    get: { settings.hidesReadArticles },
                    set: { settings.hidesReadArticles = $0 }
                ))
                Toggle("Compact Rows", isOn: Binding(
                    get: { settings.usesCompactRows },
                    set: { settings.usesCompactRows = $0 }
                ))
                Divider()
                Button("Mark All as Read", systemImage: "checkmark.circle") {
                    for article in articles where !article.isRead { article.setRead(true) }
                    try? context.save()
                }
                #if os(iOS)
                Divider()
                Button("Reading Settings…", systemImage: "textformat.size") {
                    model.isShowingSettings = true
                }
                #endif
            } label: {
                Label("View Options", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func toggleReader() {
        if model.isReaderExpanded {
            model.collapse()
        } else if let article = context.article(with: model.selectedArticleID) {
            model.open(article)
        } else if let first = scopedArticles.first {
            model.open(first)
        }
    }
}
