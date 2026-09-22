//
//  Palette.swift
//  Feed Me, Seymour!
//
//  The app is named after a carnivorous plant, so the accent is botanical.
//  Everything else defers to the system until the reader picks a paper.
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct Palette {
    var theme: ReaderTheme
    var colorScheme: ColorScheme

    private var isDark: Bool {
        theme.forcedColorScheme.map { $0 == .dark } ?? (colorScheme == .dark)
    }

    /// The reading surface.
    var paper: Color {
        switch theme {
        case .paper: Color(hex: 0xFDFAF2)
        case .night: Color(hex: 0x111315)
        case .system: isDark ? Color(hex: 0x0E0F11) : Color(hex: 0xFFFFFF)
        }
    }

    /// Chrome behind the paper: sidebars, toolbars, the timeline.
    var canvas: Color {
        switch theme {
        case .paper: Color(hex: 0xF3E9D6)
        case .night: Color(hex: 0x0A0B0C)
        case .system: isDark ? Color(hex: 0x17191C) : Color(hex: 0xF6F6F7)
        }
    }

    var ink: Color {
        switch theme {
        case .paper: Color(hex: 0x2B2723)
        case .night: Color(hex: 0xE4E2DD)
        case .system: isDark ? Color(hex: 0xEDEDEF) : Color(hex: 0x16181B)
        }
    }

    var secondaryInk: Color {
        ink.opacity(isDark ? 0.62 : 0.58)
    }

    var tertiaryInk: Color {
        ink.opacity(isDark ? 0.42 : 0.38)
    }

    var rule: Color {
        switch theme {
        case .paper: Color(hex: 0x2B2723, opacity: 0.14)
        case .night: Color(hex: 0xE4E2DD, opacity: 0.12)
        case .system: isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.09)
        }
    }

    /// Venus flytrap green.
    var accent: Color {
        isDark ? Color(hex: 0x5FD39B) : Color(hex: 0x1C7A50)
    }

    /// The star, when it's lit.
    var favorite: Color {
        isDark ? Color(hex: 0xFFC65C) : Color(hex: 0xE39B18)
    }

    var codeBackground: Color {
        switch theme {
        case .paper: Color(hex: 0x2B2723, opacity: 0.06)
        case .night: Color(hex: 0xFFFFFF, opacity: 0.06)
        case .system: isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
        }
    }

    var quoteBar: Color { accent.opacity(0.55) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(theme: .system, colorScheme: .light)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
