//
//  SubscriptionListView.swift
//  Feed Me, Seymour!
//

import SwiftUI
import SwiftData
import Combine

struct SubscriptionListView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    @Query(sort: [SortDescriptor(\Feed.sortIndex), SortDescriptor(\Feed.title)])
    private var feeds: [Feed]

    @State private var feedBeingRenamed: Feed?
    @State private var draftTitle = ""
    @State private var feedPendingRemoval: Feed?

    private var totalUnread: Int {
        feeds.reduce(0) { $0 + $1.unreadCount }
    }

    private var totalStarred: Int {
        feeds.reduce(0) { partial, feed in
            partial + feed.articles.reduce(0) { $0 + ($1.isStarred ? 1 : 0) }
        }
    }

    var body: some View {
        @Bindable var model = model

        // Through select(_:) rather than binding straight at model.selection:
        // picking a different feed has to put the reader away, or you change
        // feeds and stay staring at an article from the old one.
        let selection = Binding<FeedSelection?>(
            get: { model.selection },
            set: { new in
                guard new != model.selection else { return }
                model.select(new)
            }
        )

        List(selection: selection) {
            Section {
                // Unread first: it is what a reader opens the app to deal
                // with, and the only one of the three with a number that
                // changes while they are looking at it.
                collectionRow(.unread, title: "Unread", symbol: "circle.inset.filled", count: totalUnread)
                collectionRow(.all, title: "All Articles", symbol: "tray.full", count: nil)
                collectionRow(.starred, title: "Favorites", symbol: "star.fill", count: totalStarred)
            }

            Section("Subscriptions") {
                ForEach(feeds) { feed in
                    feedRow(feed)
                        .tag(FeedSelection.feed(feed.persistentModelID))
                }
                .onMove(perform: move)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .overlay {
            if feeds.isEmpty {
                ContentUnavailableView {
                    Label("No Subscriptions", systemImage: "leaf")
                } description: {
                    Text("Tap the button in the corner to feed the app its first URL.")
                } actions: {
                    Button("Add Subscription") { model.isShowingAddSubscription = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 70)
            }
        }
        .refreshable {
            await model.refresher.refreshAll(in: context)
        }
        .alert("Rename Subscription", isPresented: Binding(
            get: { feedBeingRenamed != nil },
            set: { if !$0 { feedBeingRenamed = nil } }
        )) {
            TextField("Title", text: $draftTitle)
            Button("Cancel", role: .cancel) { feedBeingRenamed = nil }
            Button("Save") {
                feedBeingRenamed?.customTitle = draftTitle.trimmed.nilIfEmpty
                feedBeingRenamed?.touchMetadata()
                try? context.save()
                feedBeingRenamed = nil
            }
        }
        .confirmationDialog(
            "Unsubscribe from \(feedPendingRemoval?.displayTitle ?? "")?",
            isPresented: Binding(
                get: { feedPendingRemoval != nil },
                set: { if !$0 { feedPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) {
                if let feed = feedPendingRemoval { remove(feed) }
                feedPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { feedPendingRemoval = nil }
        } message: {
            Text("Its articles will be removed. Favorites in this feed go too.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .markAllRead)) { _ in
            markAllRead()
        }
    }

    // MARK: - Rows

    private func collectionRow(_ selection: FeedSelection, title: String, symbol: String, count: Int?) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                if let count, count > 0 {
                    CountBadge(count: count)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(selection == .starred ? palette.favorite : palette.accent)
        }
        .tag(selection)
    }

    private func feedRow(_ feed: Feed) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(feed.displayTitle)
                    .lineLimit(1)
                    .foregroundStyle(palette.ink)

                if feed.lastFetchErrorDescription != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help(feed.lastFetchErrorDescription ?? "")
                }

                Spacer(minLength: 8)

                let unread = feed.unreadCount
                if unread > 0 { CountBadge(count: unread) }
            }
        } icon: {
            FeedIconView(feed: feed, size: 18)
        }
        .contextMenu { contextMenu(for: feed) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                feedPendingRemoval = feed
            } label: {
                Label("Unsubscribe", systemImage: "trash")
            }
            Button {
                Task { await model.refresher.refresh(feed, in: context) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(palette.accent)
        }
    }

    @ViewBuilder
    private func contextMenu(for feed: Feed) -> some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await model.refresher.refresh(feed, in: context) }
        }
        Button("Mark All as Read", systemImage: "checkmark.circle") {
            for article in feed.articles { article.setRead(true) }
            try? context.save()
        }
        Divider()
        Button("Rename…", systemImage: "pencil") {
            draftTitle = feed.displayTitle
            feedBeingRenamed = feed
        }
        if let home = feed.homePageURL {
            Button("Open Website", systemImage: "safari") { openURL(home) }
        }
        Button("Copy Feed URL", systemImage: "link") {
            Platform.copyToPasteboard(feed.feedURL.absoluteString)
        }
        ShareLink(item: feed.homePageURL ?? feed.feedURL)
        Divider()
        Button("Unsubscribe", systemImage: "trash", role: .destructive) {
            feedPendingRemoval = feed
        }
    }

    // MARK: - Actions

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = feeds
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, feed) in ordered.enumerated() where feed.sortIndex != index {
            feed.sortIndex = index
            feed.touchMetadata()
        }
        try? context.save()
    }

    private func remove(_ feed: Feed) {
        model.unsubscribe(feed, in: context)
    }

    private func markAllRead() {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        for article in articles where !article.isRead { article.setRead(true) }
        try? context.save()
    }
}

struct CountBadge: View {
    let count: Int
    @Environment(\.palette) private var palette

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.rule))
            .accessibilityLabel("\(count) unread")
    }
}
