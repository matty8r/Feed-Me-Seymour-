//
//  ArticleFooterView.swift
//  Feed Me, Seymour!
//
//  Where the article ends: enclosures the publisher attached, its tags, and
//  the ways out — share, open, favorite.
//

import SwiftUI
import SwiftData

struct ArticleFooterView: View {

    let article: Article

    @Environment(\.typography) private var typography
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    private var extraAttachments: [MediaAttachment] {
        // Images already appear in the body; audio and video deserve players.
        article.attachments.filter { $0.kind == .audio || $0.kind == .video || $0.kind == .document }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !extraAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Attached")
                    ForEach(extraAttachments) { attachment in
                        attachmentView(attachment)
                    }
                }
            }

            if !article.tags.isEmpty {
                tagCloud
            }

            Hairline()

            actions

            if let url = article.url {
                Text("Published at \(url.prettyHost)")
                    .font(typography.caption)
                    .foregroundStyle(palette.tertiaryInk)
            }
        }
        .frame(maxWidth: typography.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 30)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(typography.label)
            .tracking(typography.labelTracking)
            .foregroundStyle(palette.tertiaryInk)
    }

    @ViewBuilder
    private func attachmentView(_ attachment: MediaAttachment) -> some View {
        switch attachment.kind {
        case .audio:
            AudioPlayerCard(
                media: AudioMedia(
                    url: attachment.url,
                    title: attachment.title ?? article.displayTitle,
                    mimeType: attachment.mimeType,
                    artworkURL: article.bannerImageURL ?? article.feed?.effectiveIconURL,
                    duration: attachment.durationSeconds
                ),
                subtitle: article.feed?.displayTitle
            )
        case .video:
            VideoBlockView(
                media: VideoMedia(
                    url: attachment.url,
                    posterURL: article.bannerImageURL,
                    mimeType: attachment.mimeType,
                    caption: nil,
                    title: attachment.title
                )
            )
        default:
            Link(destination: attachment.url) {
                HStack(spacing: 10) {
                    Image(systemName: attachment.kind.symbolName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.title ?? attachment.url.lastPathComponent)
                            .font(typography.body)
                            .lineLimit(1)
                        if let size = attachment.formattedSize {
                            Text(size)
                                .font(typography.caption)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.codeBackground))
            }
            .buttonStyle(.plain)
        }
    }

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Tagged")
            FlowLayout(spacing: 7) {
                ForEach(article.tags.prefix(12), id: \.self) { tag in
                    Text(tag)
                        .font(typography.caption)
                        .foregroundStyle(palette.secondaryInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(palette.codeBackground))
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            StarButton(isStarred: article.isStarred, size: 16, showsLabel: true) {
                article.toggleStar()
                try? context.save()
            }

            if let url = article.url {
                ShareLink(item: url, subject: Text(article.displayTitle)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                Button {
                    openURL(url)
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .font(.callout)
        .foregroundStyle(palette.secondaryInk)
    }
}

/// A minimal flow layout for tag chips.
struct FlowLayout: Layout {
    var spacing: Double = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Double] = [0]
        var height: Double = 0
        var rowHeight: Double = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let proposed = current == 0 ? size.width : current + spacing + size.width
            if proposed > maxWidth, current > 0 {
                height += rowHeight + spacing
                rows.append(size.width)
                rowHeight = size.height
            } else {
                rows[rows.count - 1] = proposed
                rowHeight = max(rowHeight, size.height)
            }
        }
        height += rowHeight
        let widest = rows.max() ?? 0
        return CGSize(width: proposal.width ?? CGFloat(widest), height: CGFloat(height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: Double = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
