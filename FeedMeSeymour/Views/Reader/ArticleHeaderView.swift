//
//  ArticleHeaderView.swift
//  Feed Me, Seymour!
//
//  Kicker, headline, byline, lead art. The part that has to look like a
//  magazine.
//

import SwiftUI

struct ArticleHeaderView: View {

    let article: Article
    let leadImage: ImageMedia?
    var onTapImage: (ImageMedia) -> Void

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            column {
                if let feed = article.feed {
                    Text(feed.displayTitle.uppercased())
                        .font(typography.label)
                        .tracking(typography.labelTracking)
                        .foregroundStyle(palette.accent)
                        .padding(.bottom, 10)
                }

                Text(article.displayTitle)
                    .font(typography.articleTitle)
                    .tracking(typography.articleTitleTracking)
                    .lineSpacing(typography.titleLineSpacing)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                byline
                    .padding(.top, 14)
            }

            if settings.showsImages, let leadImage {
                leadArt(leadImage)
                    .padding(.top, 26)
            }
        }
        .padding(.bottom, 4)
    }

    private var byline: some View {
        HStack(spacing: 8) {
            if let author = article.author?.nilIfEmpty {
                Text(author)
                    .font(typography.byline)
                    .foregroundStyle(palette.ink.opacity(0.75))
                Text("·").foregroundStyle(palette.tertiaryInk)
            }

            Text(article.publishedAt.readerStamp)
                .font(typography.byline)
                .foregroundStyle(palette.secondaryInk)

            Text("·").foregroundStyle(palette.tertiaryInk)

            Text("\(article.readingMinutes) min read")
                .font(typography.byline)
                .foregroundStyle(palette.secondaryInk)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }

    private func leadArt(_ image: ImageMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onTapImage(image)
            } label: {
                RemoteImage(url: image.url, contentMode: .fit, aspectRatio: image.aspectRatio, cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(image.altText ?? "Lead image")

            if let caption = image.caption {
                Text(caption)
                    .font(typography.caption)
                    .lineSpacing(typography.captionLineSpacing)
                    .foregroundStyle(palette.secondaryInk)
            }
        }
        .frame(maxWidth: typography.mediaWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: typography.columnWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
    }
}
