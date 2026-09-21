//
//  EmbedView.swift
//  Feed Me, Seymour!
//
//  Third-party embeds — YouTube, Vimeo, Spotify, a Bluesky post — stay dormant
//  until the reader asks for them. Nothing is loaded, and no tracker fires,
//  from simply scrolling past.
//

import SwiftUI
import WebKit

struct EmbedView: View {

    let media: EmbedMedia

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var isActivated = false

    var body: some View {
        ZStack {
            if isActivated {
                EmbeddedWebView(url: media.url)
                    .transition(.opacity)
            } else {
                poster
            }
        }
        .aspectRatio(CGFloat(media.aspectRatio), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.rule, lineWidth: 1)
        }
        .contextMenu {
            Button("Open in Browser", systemImage: "safari") { openURL(media.canonicalURL) }
            ShareLink(item: media.canonicalURL)
            Button("Copy Link", systemImage: "link") { Platform.copyToPasteboard(media.canonicalURL.absoluteString) }
        }
    }

    private var poster: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { isActivated = true }
        } label: {
            ZStack {
                palette.codeBackground
                if let thumbnailURL = media.thumbnailURL {
                    RemoteImage(url: thumbnailURL, contentMode: .fill, showsProgress: false)
                        .overlay(Color.black.opacity(0.22))
                }

                VStack(spacing: 10) {
                    Image(systemName: media.provider.symbolName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(media.thumbnailURL == nil ? palette.accent : .white)
                        .shadow(color: .black.opacity(media.thumbnailURL == nil ? 0 : 0.35), radius: 8, y: 2)

                    Text(media.title?.nilIfEmpty ?? "Play on \(media.provider.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(media.thumbnailURL == nil ? palette.secondaryInk : .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Load \(media.provider.displayName) embed")
    }
}

#if os(iOS)
struct EmbeddedWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: EmbeddedWebView.configuration())
        view.scrollView.isScrollEnabled = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
    }
}
#else
struct EmbeddedWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: EmbeddedWebView.configuration())
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
    }
}
#endif

extension EmbeddedWebView {
    /// Inline playback, no data left behind.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        return configuration
    }
}
