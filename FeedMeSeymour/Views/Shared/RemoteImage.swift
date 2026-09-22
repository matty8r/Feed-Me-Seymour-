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
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.28))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .failure:
                placeholder(symbol: "photo.badge.exclamationmark")
            case .empty:
                if showsProgress {
                    placeholder(symbol: nil)
                } else {
                    Color.clear
                }
            @unknown default:
                placeholder(symbol: nil)
            }
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
