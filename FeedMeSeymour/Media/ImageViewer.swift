//
//  ImageViewer.swift
//  Feed Me, Seymour!
//
//  Tap a photograph and it fills the screen: pinch to zoom, drag to pan, flick
//  down to dismiss, share from the corner.
//

import SwiftUI

struct ImageViewer: View {

    let image: ImageMedia
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @Environment(\.openURL) private var openURL

    private var isZoomed: Bool { committedZoom > 1.01 }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(1 - min(abs(offset.height) / 600, 0.55))

            RemoteImage(url: image.url, contentMode: .fit, showsProgress: true)
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(magnification)
                .simultaneousGesture(pan)
                .onTapGesture(count: 2) { toggleZoom() }
                .ignoresSafeArea()

            VStack {
                controls
                Spacer()
                if let caption = image.caption ?? image.altText.map({ AttributedString($0) }) {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                        .shadow(radius: 6)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: zoom)
        .accessibilityAddTraits(.isImage)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")

            Spacer()

            if let linkURL = image.linkURL {
                Button { openURL(linkURL) } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Open Link")
            }

            ShareLink(item: image.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Share Image")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = max(1, min(committedZoom * value.magnification, 8))
            }
            .onEnded { _ in
                committedZoom = zoom
                if committedZoom <= 1.01 { resetPosition() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                // Flick down on an unzoomed image to dismiss, the way Photos does.
                if !isZoomed, value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    onClose()
                    return
                }
                if isZoomed {
                    committedOffset = offset
                } else {
                    resetPosition()
                }
            }
    }

    private func toggleZoom() {
        if isZoomed {
            committedZoom = 1
            zoom = 1
            resetPosition()
        } else {
            committedZoom = 2.5
            zoom = 2.5
        }
    }

    private func resetPosition() {
        offset = .zero
        committedOffset = .zero
    }
}

// MARK: - Presentation

extension View {
    /// Presents the lightbox in whichever way the platform expects.
    @ViewBuilder
    func imageViewer(item: Binding<ImageMedia?>) -> some View {
        #if os(iOS)
        fullScreenCover(item: item) { image in
            ImageViewer(image: image) { item.wrappedValue = nil }
        }
        #else
        sheet(item: item) { image in
            ImageViewer(image: image) { item.wrappedValue = nil }
                .frame(minWidth: 680, minHeight: 480)
        }
        #endif
    }
}
