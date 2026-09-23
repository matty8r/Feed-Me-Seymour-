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
    @State private var voices: [SpeechVoice] = []

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

            Section("Read Aloud") {
                Picker("Voice", selection: Binding(
                    get: { settings.voiceIdentifier ?? "" },
                    set: { settings.voiceIdentifier = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(voices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }

                LabeledContent("Speed") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.speechRate, in: ReaderSettings.speechRateRange, step: 0.05)
                        Text(settings.speechRateLabel)
                            .font(.callout.monospacedDigit())
                            .frame(width: 48, alignment: .trailing)
                    }
                    .frame(minWidth: 220)
                }

                LabeledContent("Pitch") {
                    Slider(value: $settings.speechPitch, in: ReaderSettings.speechPitchRange, step: 0.05)
                        .frame(minWidth: 180)
                }

                Toggle("Describe images", isOn: $settings.announcesImagesAloud)
                Toggle("Continue to the next article", isOn: $settings.autoAdvancesSpeech)

                if SpeechVoiceCatalog.canRequestPersonalVoice {
                    Button("Allow Personal Voice…") {
                        Task { @MainActor in
                            _ = await SpeechVoiceCatalog.requestPersonalVoiceAccess()
                            voices = SpeechVoiceCatalog.voices(for: nil)
                        }
                    }
                }

                Text("Code listings and tables are announced rather than read out. Articles in another language are read by a matching voice when one is installed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

            Section("iCloud") {
                Toggle("Sync with iCloud", isOn: Binding(
                    get: { model.sync.isEnabled },
                    set: { model.sync.isEnabled = $0 }
                ))
                .disabled(!model.sync.isCloudBacked)

                HStack(spacing: 7) {
                    if model.sync.needsRelaunch || model.sync.isFailing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(model.sync.statusDescription)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                // Every other push is a side effect of refreshing, closing the
                // app or opening it. That is fine until you are trying to find
                // out whether sync works, which is exactly when you want to ask
                // it directly and be told what happened.
                Button("Sync Now") {
                    model.sync.reconcile(in: context)
                }
                .disabled(!model.sync.isActive || model.sync.isSyncing)

                Text("Subscriptions, favorites and read state travel between your devices. Article text and media stay on each device and are re-downloaded from the publisher when needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                Text("No account, no analytics. Feeds are fetched straight from their publishers, and anything that syncs goes only to your own private iCloud database.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { voices = SpeechVoiceCatalog.voices(for: nil) }
        .onChange(of: settings.speechRate) { _, _ in SpeechReader.shared.reapply(settings: settings) }
        .onChange(of: settings.voiceIdentifier) { _, _ in SpeechReader.shared.reapply(settings: settings) }
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
