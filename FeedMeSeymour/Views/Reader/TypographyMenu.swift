//
//  TypographyMenu.swift
//  Feed Me, Seymour!
//
//  The `aA` control. Size, face, measure and paper, all live.
//

import SwiftUI

/// The `aA` control as its own button in the bar.
struct TypographyMenu: View {
    var body: some View {
        Menu {
            TypographyMenuItems()
        } label: {
            Image(systemName: "textformat").barGlyph()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reading Settings")
    }
}

/// The same controls as menu rows, so they can also hang off the overflow menu
/// where the bar is too narrow to spend a slot on them.
struct TypographyMenuItems: View {

    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Group {
            Section("Text Size") {
                Button("Bigger", systemImage: "textformat.size.larger") { settings.nudgeSize(by: 1) }
                    .disabled(!settings.canGrow)
                Button("Smaller", systemImage: "textformat.size.smaller") { settings.nudgeSize(by: -1) }
                    .disabled(!settings.canShrink)
                Button("Reset", systemImage: "arrow.counterclockwise") { settings.resetTypography() }
            }

            Picker("Typeface", selection: $settings.face) {
                ForEach(ReadingFace.allCases) { face in
                    Text(face.displayName).tag(face)
                }
            }

            Picker("Line Width", selection: $settings.measure) {
                ForEach(ReadingMeasure.allCases) { measure in
                    Text(measure.displayName).tag(measure)
                }
            }

            Picker("Paper", selection: $settings.theme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Label(theme.displayName, systemImage: theme.symbolName).tag(theme)
                }
            }

            Divider()

            Toggle("Show Images", isOn: $settings.showsImages)
            Toggle("Mark Read When Opened", isOn: $settings.marksReadOnOpen)
        }
    }
}
