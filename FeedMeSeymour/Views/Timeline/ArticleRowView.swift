//
//  ArticleRowView.swift
//  Feed Me, Seymour!
//
//  One entry in the chronological list: where it came from, when, what it is,
//  and a star.
//

import SwiftUI
import SwiftData

struct ArticleRowView: View {

    let article: Article
    var showsFeedName = true
    var onOpen: () -> Void

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var isHovering = false

    private var isCompact: Bool { settings.usesCompactRows }

    private var thumbnailURL: URL? {
        guard settings.showsImages else { return nil }
        if let banner = article.bannerImageURL { return banner }
        return article.attachments.first(where: { $0.kind == .image })?.url
    }

    /// A square, so a column of rows has a straight edge down the right
    /// whatever shape the pictures themselves are.
    private var thumbnailSide: CGFloat { isCompact ? 54 : 84 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            unreadDot

            VStack(alignment: .leading, spacing: isCompact ? 3 : 6) {
                sourceLine
                title
                if !isCompact { dek }
                footer
            }
            // Claim the space the thumbnail doesn't, so the text lays out
            // against a known width instead of against the picture.
            .frame(maxWidth: .infinity, alignment: .leading)

            if let thumbnailURL {
                // A plain fixed square. Letting it track the row height instead
                // — maxHeight .infinity with a 1:1 ratio — makes it flexible on
                // both axes, and an HStack hands a view like that the whole row.
                RemoteImage(url: thumbnailURL, contentMode: .fill, cornerRadius: 8)
                    .frame(width: thumbnailSide, height: thumbnailSide)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.rule, lineWidth: 0.5)
                    }
                    .padding(.leading, 2)
            }
        }
        // So a one-line row is still tall enough to seat the square.
        .frame(minHeight: thumbnailURL == nil ? 0 : thumbnailSide)
        .padding(.vertical, isCompact ? 8 : 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        // One click opens it, on both platforms. Opening also selects, so the
        // row you clicked is the current one when you come back out.
        .onTapGesture { onOpen() }
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                article.setRead(!article.isRead)
                try? context.save()
            } label: {
                Label(article.isRead ? "Unread" : "Read", systemImage: article.isRead ? "circle" : "checkmark.circle")
            }
            .tint(palette.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                article.toggleStar()
                try? context.save()
            } label: {
                Label("Favorite", systemImage: article.isStarred ? "star.slash" : "star")
            }
            .tint(palette.favorite)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var unreadDot: some View {
        Circle()
            .fill(article.isRead ? Color.clear : palette.accent)
            .frame(width: 7, height: 7)
            .padding(.top, 7)
            .animation(.easeOut(duration: 0.2), value: article.isRead)
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            if showsFeedName, let feed = article.feed {
                FeedIconView(feed: feed, size: 13)
                Text(feed.displayTitle)
                    .lineLimit(1)
            }
            if showsFeedName, article.feed != nil {
                Text("·").foregroundStyle(palette.tertiaryInk)
            }
            Text(article.publishedAt.timelineStamp)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(palette.secondaryInk)
    }

    private var title: some View {
        Text(article.displayTitle)
            .font(.system(size: isCompact ? 15 : 17, weight: article.isRead ? .regular : .semibold, design: .serif))
            .foregroundStyle(article.isRead ? palette.secondaryInk : palette.ink)
            .lineSpacing(1.5)
            .lineLimit(isCompact ? 1 : 3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var dek: some View {
        if !article.plainSummary.isEmpty {
            Text(article.plainSummary)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.secondaryInk)
                .lineSpacing(2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(article.readingMinutes) min")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.tertiaryInk)

            if article.hasAudio {
                mediaBadge("waveform", "Audio")
            }
            if article.hasVideo {
                mediaBadge("play.rectangle", "Video")
            }
            if article.isPlaceholder {
                mediaBadge("icloud", "Favorited on another device")
            }
            if let author = article.author?.nilIfEmpty, !isCompact {
                Text(author)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            StarButton(isStarred: article.isStarred, size: 14) {
                article.toggleStar()
                try? context.save()
            }
            .opacity(article.isStarred || isHovering || Platform.isPhone ? 1 : 0.55)
        }
        .padding(.top, 1)
    }

    private func mediaBadge(_ symbol: String, _ label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.tertiaryInk)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Read", systemImage: "book") { onOpen() }
        Button("Read Aloud", systemImage: "speaker.wave.2") {
            SpeechReader.shared.start(
                article: article,
                rendered: ArticleRenderer.shared.render(article),
                settings: settings
            )
        }
        Button(article.isStarred ? "Remove from Favorites" : "Add to Favorites", systemImage: article.isStarred ? "star.slash" : "star") {
            article.toggleStar()
            try? context.save()
        }
        Button(article.isRead ? "Mark as Unread" : "Mark as Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
            article.setRead(!article.isRead)
            try? context.save()
        }
        Divider()
        if let url = article.url {
            Button("Open in Browser", systemImage: "safari") { openURL(url) }
            ShareLink(item: url, subject: Text(article.displayTitle))
            Button("Copy Link", systemImage: "link") { Platform.copyToPasteboard(url.absoluteString) }
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let feed = article.feed { parts.append(feed.displayTitle) }
        parts.append(article.displayTitle)
        parts.append(article.publishedAt.relativeStamp)
        parts.append("\(article.readingMinutes) minute read")
        if article.isStarred { parts.append("Favorite") }
        if !article.isRead { parts.append("Unread") }
        return parts.joined(separator: ", ")
    }
}
