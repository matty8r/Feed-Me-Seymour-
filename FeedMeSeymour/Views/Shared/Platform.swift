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
