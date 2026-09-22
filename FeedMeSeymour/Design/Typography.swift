//
//  Typography.swift
//  Feed Me, Seymour!
//
//  The reader's type scale. Sizes are the reader's own choice multiplied by the
//  system's Dynamic Type setting, so accessibility sizes work even when someone
//  has dialled the article text down.
//
//  Outside the reader (sidebar, timeline, sheets) the app uses semantic text
//  styles instead, so the rest of the UI matches every other Apple app.
//

import SwiftUI

extension DynamicTypeSize {
    /// Apple's own ramp, normalized so `.large` — the system default — is 1.0.
    var typeScale: Double {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1.0
        case .xLarge: 1.08
        case .xxLarge: 1.17
        case .xxxLarge: 1.27
        case .accessibility1: 1.45
        case .accessibility2: 1.65
        case .accessibility3: 1.9
        case .accessibility4: 2.15
        case .accessibility5: 2.4
        @unknown default: 1.0
        }
    }
}

struct Typography: Equatable {

    var face: ReadingFace
    var measure: ReadingMeasure
    var lineHeightMultiple: Double
    var scaledBaseSize: Double

    init(face: ReadingFace = .serif, measure: ReadingMeasure = .comfortable, baseSize: Double = 19, lineHeight: Double = 1.58, typeScale: Double = 1) {
        self.face = face
        self.measure = measure
        self.lineHeightMultiple = lineHeight
        self.scaledBaseSize = (baseSize + face.opticalSizeAdjustment) * typeScale
    }

    init(settings: ReaderSettings, dynamicTypeSize: DynamicTypeSize) {
        self.init(
            face: settings.face,
            measure: settings.measure,
            baseSize: settings.baseSize,
            lineHeight: settings.lineHeight,
            typeScale: dynamicTypeSize.typeScale
        )
    }

    private var design: Font.Design { face.design }

    private func font(_ multiplier: Double, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        .system(size: (scaledBaseSize * multiplier).rounded(), weight: weight, design: design ?? self.design)
    }

    // MARK: Display

    /// The headline. Always serif: it's the app's signature.
    var articleTitle: Font { .system(size: (scaledBaseSize * 2.05).rounded(), weight: .semibold, design: .serif) }
    var articleTitleTracking: Double { -(scaledBaseSize * 2.05) * 0.016 }

    var dek: Font { font(1.12, weight: .regular) }
    var byline: Font { .system(size: (scaledBaseSize * 0.82).rounded(), weight: .medium, design: .default) }

    // MARK: Body

    var body: Font { font(1.0) }
    var bodyBold: Font { font(1.0, weight: .semibold) }

    var heading2: Font { .system(size: (scaledBaseSize * 1.48).rounded(), weight: .semibold, design: .serif) }
    var heading3: Font { .system(size: (scaledBaseSize * 1.22).rounded(), weight: .semibold, design: .serif) }
    var heading4: Font { font(1.04, weight: .semibold) }

    func heading(level: Int) -> Font {
        switch level {
        case 1, 2: heading2
        case 3: heading3
        default: heading4
        }
    }

    func headingTopPadding(level: Int) -> Double {
        switch level {
        case 1, 2: scaledBaseSize * 1.5
        case 3: scaledBaseSize * 1.25
        default: scaledBaseSize * 1.0
        }
    }

    var quote: Font { .system(size: (scaledBaseSize * 1.06).rounded(), weight: .regular, design: .serif) }
    var pullQuote: Font { .system(size: (scaledBaseSize * 1.4).rounded(), weight: .medium, design: .serif) }
    var caption: Font { .system(size: (scaledBaseSize * 0.8).rounded(), weight: .regular, design: .default) }
    var code: Font { .system(size: (scaledBaseSize * 0.86).rounded(), weight: .regular, design: .monospaced) }
    var tableCell: Font { .system(size: (scaledBaseSize * 0.88).rounded(), weight: .regular, design: .default) }

    /// Small caps and wide tracking for datelines and section labels.
    var label: Font { .system(size: (scaledBaseSize * 0.72).rounded(), weight: .semibold, design: .default) }
    var labelTracking: Double { scaledBaseSize * 0.72 * 0.08 }

    // MARK: Rhythm

    /// SwiftUI's `lineSpacing` is *extra* leading, so subtract the font's own.
    private func leading(for size: Double, multiple: Double? = nil) -> Double {
        let target = size * (multiple ?? lineHeightMultiple)
        let intrinsic = size * 1.21
        return max(0, target - intrinsic)
    }

    var bodyLineSpacing: Double { leading(for: scaledBaseSize) }
    var quoteLineSpacing: Double { leading(for: scaledBaseSize * 1.06) }
    var headingLineSpacing: Double { leading(for: scaledBaseSize * 1.48, multiple: min(lineHeightMultiple, 1.28)) }
    var titleLineSpacing: Double { leading(for: scaledBaseSize * 2.05, multiple: 1.12) }
    var captionLineSpacing: Double { leading(for: scaledBaseSize * 0.8, multiple: 1.4) }

    /// The space between paragraphs — a shade under one blank line.
    var paragraphSpacing: Double { (scaledBaseSize * 0.92).rounded() }
    var blockSpacing: Double { (scaledBaseSize * 1.35).rounded() }

    /// The text column, in points.
    var columnWidth: Double {
        measure.points * min(max(scaledBaseSize / 19, 0.85), 1.6)
    }

    /// Media is allowed to outdent a little past the text.
    var mediaWidth: Double { columnWidth * 1.12 }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography()
}

extension EnvironmentValues {
    var typography: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}
