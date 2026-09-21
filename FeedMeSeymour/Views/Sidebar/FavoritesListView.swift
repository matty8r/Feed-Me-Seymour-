//
//  FavoritesListView.swift
//  Feed Me, Seymour!
//
//  Everything the reader starred, newest first. Picking one opens it straight
//  into the reader on the right.
//

import SwiftUI
import SwiftData

struct FavoritesListView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette

    @Query(
        filter: #Predicate<Article> { $0.isStarred },
        sort: [SortDescriptor(\Article.starredAt, order: .reverse), SortDescriptor(\Article.publishedAt, order: .reverse)]
    )
    private var favorites: [Article]

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedArticleID) {
            if !favorites.isEmpty {
                Section {
                    Button {
                        model.select(.starred)
                    } label: {
                        Label {
                            HStack {
                                Text("All Favorites")
                                Spacer(minLength: 8)
                                CountBadge(count: favorites.count)
                            }
                        } icon: {
                            Image(systemName: "star.fill").foregroundStyle(palette.favorite)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(favorites.isEmpty ? "" : "Starred Articles") {
                ForEach(favorites) { article in
                    row(article)
                        .tag(article.persistentModelID)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No Favorites Yet", systemImage: "star")
                } description: {
                    Text("Tap the star on any article and it will wait for you here.")
                }
            }
        }
        .onChange(of: model.selectedArticleID) { _, id in
            // Choosing a favourite should open it, not merely highlight it.
            guard model.sidebarTab == .favorites, let article = context.article(with: id), article.isStarred else { return }
            if model.selection != .starred { model.selection = .starred }
            model.open(article)
        }
    }

    private func row(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(article.displayTitle)
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 5) {
                if let feed = article.feed {
                    Text(feed.displayTitle).lineLimit(1)
                    Text("·")
                }
                Text(article.publishedAt.timelineStamp)
            }
            .font(.caption)
            .foregroundStyle(palette.tertiaryInk)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Remove from Favorites", systemImage: "star.slash") {
                article.toggleStar()
                try? context.save()
            }
            if let url = article.url {
                ShareLink(item: url)
                Button("Copy Link", systemImage: "link") {
                    Platform.copyToPasteboard(url.absoluteString)
                }
            }
        }
    }
}
