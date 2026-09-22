//
//  FeedIconView.swift
//  Feed Me, Seymour!
//
//  A feed's mark, or a tidy monogram when it hasn't got one.
//

import SwiftUI

struct FeedIconView: View {

    let feed: Feed
    var size: Double = 20

    @Environment(\.palette) private var palette

    private var monogram: String {
        let title = feed.displayTitle.trimmed
        guard let first = title.first else { return "?" }
        return String(first).uppercased()
    }

    /// A stable colour per feed, so the sidebar reads at a glance.
    private var tint: Color {
        let hash = abs(feed.feedURL.absoluteString.hashValue)
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.42, brightness: 0.78)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.22))

            if let url = feed.effectiveIconURL {
                RemoteImage(url: url, contentMode: .fill, showsProgress: false, cornerRadius: size * 0.28)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}
