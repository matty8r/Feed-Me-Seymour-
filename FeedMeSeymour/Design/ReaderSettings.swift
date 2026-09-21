//
//  ReaderSettings.swift
//  Feed Me, Seymour!
//

import SwiftUI
import Observation

enum ReadingFace: String, CaseIterable, Identifiable, Codable {
    case serif, sans, rounded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .serif: "New York"
        case .sans: "SF Pro"
        case .rounded: "SF Rounded"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }

    /// Serif faces read a hair larger at the same point size.
    var opticalSizeAdjustment: Double {
        switch self {
        case .serif: -0.5
        case .sans: 0
        case .rounded: 0
        }
    }
}

enum ReadingMeasure: String, CaseIterable, Identifiable, Codable {
    case narrow, comfortable, wide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .narrow: "Narrow"
        case .comfortable: "Comfortable"
        case .wide: "Wide"
        }
    }

    /// Roughly 55, 68 and 82 characters per line at the default size.
    var points: Double {
        switch self {
        case .narrow: 560
        case .comfortable: 680
        case .wide: 820
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case system, paper, night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .paper: "Paper"
        case .night: "Night"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .paper: "book.closed"
        case .night: "moon.stars"
        }
    }

    var forcedColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .paper: .light
        case .night: .dark
        }
    }
}

@Observable
final class ReaderSettings {

    private enum Key {
        static let face = "reader.face"
        static let measure = "reader.measure"
        static let theme = "reader.theme"
        static let baseSize = "reader.baseSize"
        static let lineHeight = "reader.lineHeight"
        static let showsImages = "reader.showsImages"
        static let markReadOnOpen = "reader.markReadOnOpen"
        static let refreshMinutes = "reader.refreshMinutes"
        static let compactRows = "timeline.compactRows"
        static let hidesRead = "timeline.hidesRead"
    }

    static let sizeRange: ClosedRange<Double> = 15...26
    static let lineHeightRange: ClosedRange<Double> = 1.35...1.9

    var face: ReadingFace { didSet { store(face.rawValue, Key.face) } }
    var measure: ReadingMeasure { didSet { store(measure.rawValue, Key.measure) } }
    var theme: ReaderTheme { didSet { store(theme.rawValue, Key.theme) } }
    var baseSize: Double { didSet { store(baseSize, Key.baseSize) } }
    var lineHeight: Double { didSet { store(lineHeight, Key.lineHeight) } }
    var showsImages: Bool { didSet { store(showsImages, Key.showsImages) } }
    var marksReadOnOpen: Bool { didSet { store(marksReadOnOpen, Key.markReadOnOpen) } }
    var refreshMinutes: Int { didSet { store(refreshMinutes, Key.refreshMinutes) } }
    var usesCompactRows: Bool { didSet { store(usesCompactRows, Key.compactRows) } }
    var hidesReadArticles: Bool { didSet { store(hidesReadArticles, Key.hidesRead) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        face = ReadingFace(rawValue: defaults.string(forKey: Key.face) ?? "") ?? .serif
        measure = ReadingMeasure(rawValue: defaults.string(forKey: Key.measure) ?? "") ?? .comfortable
        theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        baseSize = defaults.object(forKey: Key.baseSize) as? Double ?? 19
        lineHeight = defaults.object(forKey: Key.lineHeight) as? Double ?? 1.58
        showsImages = defaults.object(forKey: Key.showsImages) as? Bool ?? true
        marksReadOnOpen = defaults.object(forKey: Key.markReadOnOpen) as? Bool ?? true
        refreshMinutes = defaults.object(forKey: Key.refreshMinutes) as? Int ?? 30
        usesCompactRows = defaults.object(forKey: Key.compactRows) as? Bool ?? false
        hidesReadArticles = defaults.object(forKey: Key.hidesRead) as? Bool ?? false
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    func nudgeSize(by delta: Double) {
        baseSize = min(max(baseSize + delta, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    func resetTypography() {
        face = .serif
        measure = .comfortable
        baseSize = 19
        lineHeight = 1.58
    }

    var canGrow: Bool { baseSize < Self.sizeRange.upperBound }
    var canShrink: Bool { baseSize > Self.sizeRange.lowerBound }
}
