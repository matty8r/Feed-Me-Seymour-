//
//  SettingsView.swift
//  Feed Me, Seymour!
//
//  The macOS Settings window, and the same content in a sheet on iOS.
//

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query private var feeds: [Feed]

    private var palette: Palette { Palette(theme: settings.theme, colorScheme: colorScheme) }
    private var typography: Typography { Typography(settings: settings, dynamicTypeSize: dynamicTypeSize) }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Reading") {
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

                LabeledContent("Text Size") {
                    HStack(spacing: 10) {
                        Text("A").font(.system(size: 11))
                        Slider(
                            value: $settings.baseSize,
                            in: ReaderSettings.sizeRange,
                            step: 1
                        )
                        Text("A").font(.system(size: 19))
                    }
                    .frame(minWidth: 180)
                }

                LabeledContent("Line Spacing") {
                    Slider(value: $settings.lineHeight, in: ReaderSettings.lineHeightRange, step: 0.02)
                        .frame(minWidth: 180)
                }
            }

            Section("Preview") {
                specimen
            }

            Section("Timeline") {
                Toggle("Hide read articles", isOn: $settings.hidesReadArticles)
                Toggle("Compact rows", isOn: $settings.usesCompactRows)
                Toggle("Show images", isOn: $settings.showsImages)
                Toggle("Mark as read when opened", isOn: $settings.marksReadOnOpen)
            }

            Section("Subscriptions") {
                Picker("Refresh every", selection: $settings.refreshMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                    Text("Manually").tag(100_000)
                }

                LabeledContent("Subscriptions", value: "\(feeds.count)")

                HStack {
                    Button("Import OPML…") { model.isShowingOPMLImporter = true }
                    Button("Export OPML…") { model.isShowingOPMLExporter = true }
                }
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                Text("Feed Me, Seymour! keeps everything on your device. No account, no analytics, no server in the middle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #else
        .frame(width: 560, height: 620)
        #endif
    }

    private var specimen: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feed me, Seymour!")
                .font(typography.heading3)
                .foregroundStyle(palette.ink)
            Text("Suddenly Seymour — the type should feel like it was set by somebody who cared, and it should stay readable at every size the system asks for.")
                .font(typography.body)
                .lineSpacing(typography.bodyLineSpacing)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.paper))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.rule))
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
