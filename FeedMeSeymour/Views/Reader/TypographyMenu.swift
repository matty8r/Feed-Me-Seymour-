//
//  TypographyMenu.swift
//  Feed Me, Seymour!
//
//  The `aA` control. Size, face, measure and paper, all live.
//

import SwiftUI

struct TypographyMenu: View {

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var settings = settings

        Menu {
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
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .medium))
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reading Settings")
    }
}
