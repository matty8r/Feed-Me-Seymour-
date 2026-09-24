//
//  Platform.swift
//  Feed Me, Seymour!
//
//  The handful of places where macOS and iOS genuinely differ.
//

import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// Whether the pasteboard is holding something that looks like a link.
    ///
    /// On iOS this is the only question that can be asked without the system
    /// putting up a paste confirmation, so it is the one asked on the way in;
    /// the contents are read only when someone presses a paste button. On the
    /// Mac there is no such prompt, so the link can simply be read.
    static var pasteboardHasLink: Bool {
        #if os(macOS)
        pasteboardLink != nil
        #else
        UIPasteboard.general.hasURLs
        #endif
    }

    /// The pasteboard's contents, if they could plausibly be a feed or a site.
    /// Reading this on iOS shows a paste confirmation; prefer a `PasteButton`.
    static var pasteboardLink: String? {
        #if os(macOS)
        linkLike(NSPasteboard.general.string(forType: .string))
        #else
        UIPasteboard.general.url?.absoluteString ?? linkLike(UIPasteboard.general.string)
        #endif
    }

    /// Deliberately loose: the add sheet already takes a bare host, so this
    /// only has to rule out prose. A single token with a dot in it will do.
    private static func linkLike(_ raw: String?) -> String? {
        guard let candidate = raw?.trimmed, !candidate.isEmpty else { return nil }
        guard candidate.count <= 2048, !candidate.contains(where: \.isNewline) else { return nil }
        if candidate.hasPrefix("http://") || candidate.hasPrefix("https://") || candidate.hasPrefix("feed://") {
            return candidate
        }
        guard !candidate.contains(" "), candidate.contains(".") else { return nil }
        return candidate
    }

    static func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

/// A hairline that stays a hairline on every display.
struct Hairline: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: 1 / displayScale)
    }

    @Environment(\.displayScale) private var displayScale
}

extension View {
    /// Applies a modifier only when the condition holds. Used sparingly, for
    /// platform-specific chrome.
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
