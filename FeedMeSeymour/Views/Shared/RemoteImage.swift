//
//  RemoteImage.swift
//  Feed Me, Seymour!
//
//  Every image in a feed is a remote image. They should fade in, keep their
//  shape while loading, animate when they're GIFs, and never blow up the layout.
//

import SwiftUI

struct RemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill
    var aspectRatio: Double?
    var showsProgress = true
    var cornerRadius: Double = 0

    @Environment(\.palette) private var palette

    private var isAnimated: Bool {
        url?.pathExtension.lowercased() == "gif"
    }

    var body: some View {
        sized
            // A .fill image scales past the frame on its short axis — that is
            // the point of filling. Without this it isn't cropped, it just
            // draws over whatever is beside it.
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Only impose a ratio when the caller knows one. Asking for
    /// `.aspectRatio(nil, contentMode: .fill)` lets the loaded image report its
    /// own proportions as the layout size, so a square placeholder becomes a
    /// wide photo the moment it arrives, and the frame around it no longer
    /// describes what's drawn.
    @ViewBuilder
    private var sized: some View {
        if let aspectRatio {
            content.aspectRatio(CGFloat(aspectRatio), contentMode: contentMode)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAnimated, let url {
            AnimatedImageView(url: url, contentMode: contentMode)
        } else {
            staticImage
        }
    }

    @ViewBuilder
    private var staticImage: some View {
        // Not AsyncImage: it re-fetches and re-decodes every time the view is
        // built, which is constantly. ImageStore hands back an already-decoded
        // picture, so a rebuilt view shows it immediately rather than blinking
        // through a placeholder on the way.
        CachedImage(url: url, contentMode: contentMode, showsProgress: showsProgress) { symbol in
            placeholder(symbol: symbol)
        }
    }

    @ViewBuilder
    private func placeholder(symbol: String?) -> some View {
        ZStack {
            palette.codeBackground
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.tertiaryInk)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}


// MARK: - The loading view

private struct CachedImage<Placeholder: View>: View {

    let url: URL?
    let contentMode: ContentMode
    let showsProgress: Bool
    @ViewBuilder var placeholder: (String?) -> Placeholder

    @State private var loaded: PlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = loaded ?? url.flatMap({ ImageStore.shared.cached($0) }) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                placeholder("photo.badge.exclamationmark")
            } else if showsProgress {
                placeholder(nil)
            } else {
                Color.clear
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        // Straight from the cache is not worth a state change or a fade.
        if ImageStore.shared.cached(url) != nil { return }

        let image = await ImageStore.shared.image(for: url)
        guard !Task.isCancelled else { return }
        if let image {
            withAnimation(.easeOut(duration: 0.28)) { loaded = image }
        } else {
            failed = true
        }
    }
}
