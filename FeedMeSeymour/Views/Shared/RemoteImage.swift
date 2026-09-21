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
        Group {
            if isAnimated, let url {
                AnimatedImageView(url: url, contentMode: contentMode)
            } else {
                staticImage
            }
        }
        .aspectRatio(aspectRatio.map { CGFloat($0) }, contentMode: contentMode)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
