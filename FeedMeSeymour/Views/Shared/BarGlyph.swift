//
//  BarGlyph.swift
//  Feed Me, Seymour!
//
//  The reader's top bar and the speech transport are different bars doing
//  different jobs, but they sit in the same window and the eye reads them as
//  one family. So every glyph in either of them comes through here: one size,
//  one weight, one colour, and one hit target big enough to actually hit.
//

import SwiftUI

enum BarGlyph {
    /// Point size for every icon in either bar.
    static let size: CGFloat = 15
    static let weight: Font.Weight = .medium

    /// The tappable box around each glyph. A bare SF Symbol is a ~15pt target,
    /// which is fine with a mouse and hopeless with a thumb.
    static let hit = CGSize(width: 34, height: 32)

    /// The close chevron outranks the rest of the bar, so it is drawn larger.
    static let closeSize: CGFloat = 20
}

extension View {
    /// Uniform size, weight and hit area for a bar icon. Colour is inherited
    /// from the bar, so don't tint at the call site unless the icon means
    /// something by it — an active state, or the lit star.
    func barGlyph(size: CGFloat = BarGlyph.size,
                  weight: Font.Weight = BarGlyph.weight,
                  width: CGFloat = BarGlyph.hit.width) -> some View {
        font(.system(size: size, weight: weight))
            .frame(width: width, height: BarGlyph.hit.height)
            .contentShape(Rectangle())
    }

    /// The way out of the reader. Deliberately larger than its neighbours —
    /// it's the one control you reach for without looking.
    func closeGlyph() -> some View {
        barGlyph(size: BarGlyph.closeSize, weight: .semibold, width: 40)
    }
}
