//
//  SpeechBar.swift
//  Feed Me, Seymour!
//
//  The transport for reading aloud. It lives at the root rather than inside the
//  reader, so closing the article doesn't leave a voice you can't stop.
//

import SwiftUI
import AVFoundation

struct SpeechBar: View {

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    private var speech: SpeechReader { .shared }

    var body: some View {
        if speech.isActive {
            content
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ProgressView(value: speech.progress)
                .progressViewStyle(.linear)
                .tint(palette.accent)
                .frame(height: 2)

            HStack(spacing: 0) {
                Image(systemName: "waveform")
                    .foregroundStyle(palette.accent)
                    .symbolEffect(.variableColor.iterative, isActive: speech.isSpeaking && !speech.isPaused)
                    .barGlyph()

                VStack(alignment: .leading, spacing: 1) {
                    Text(speech.articleTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(palette.ink)
                    Text(positionLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.tertiaryInk)
                        .monospacedDigit()
                }
                .padding(.leading, 2)

                Spacer(minLength: 8)

                Button { speech.skipBackward() } label: {
                    Image(systemName: "backward.end.fill").barGlyph()
                }
                .buttonStyle(.plain)
                .help("Previous Paragraph")

                // The one glyph in either bar that breaks the rule, on
                // purpose: it is the primary action of the transport.
                Button { speech.toggle() } label: {
                    ZStack {
                        Circle().fill(palette.accent)
                        Image(systemName: speech.isPaused || !speech.isSpeaking ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: BarGlyph.hit.height, height: BarGlyph.hit.height)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(speech.isPaused ? "Resume" : "Pause")

                Button { speech.skipForward() } label: {
                    Image(systemName: "forward.end.fill").barGlyph()
                }
                .buttonStyle(.plain)
                .help("Next Paragraph")

                SpeechVoiceMenu()

                Button { speech.stop() } label: {
                    Image(systemName: "xmark").barGlyph()
                }
                .buttonStyle(.plain)
                .help("Stop Reading")
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reading \(speech.articleTitle) aloud")
    }

    private var positionLabel: String {
        "Paragraph \(speech.currentIndex + 1) of \(speech.segments.count) · \(settings.speechRateLabel)"
    }
}

// MARK: - Voice and rate

struct SpeechVoiceMenu: View {

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var voices: [SpeechVoice] = []
    @State private var isRequestingPersonalVoice = false

    private var speech: SpeechReader { .shared }

    var body: some View {
        @Bindable var settings = settings

        Menu {
            Section("Speed") {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                    Button {
                        settings.speechRate = value
                        speech.reapply(settings: settings)
                    } label: {
                        if settings.speechRate == value {
                            Label(label(for: value), systemImage: "checkmark")
                        } else {
                            Text(label(for: value))
                        }
                    }
                }
            }

            if !voices.isEmpty {
                Section("Voice") {
                    Button {
                        settings.voiceIdentifier = nil
                        speech.reapply(settings: settings)
                    } label: {
                        if settings.voiceIdentifier == nil {
                            Label("System Default", systemImage: "checkmark")
                        } else {
                            Text("System Default")
                        }
                    }

                    ForEach(voices) { voice in
                        Button {
                            settings.voiceIdentifier = voice.id
                            speech.reapply(settings: settings)
                        } label: {
                            if settings.voiceIdentifier == voice.id {
                                Label(voice.displayName, systemImage: "checkmark")
                            } else {
                                Text(voice.displayName)
                            }
                        }
                    }
                }
            }

            if SpeechVoiceCatalog.canRequestPersonalVoice {
                Divider()
                Button("Use Personal Voice…", systemImage: "waveform.badge.person") {
                    requestPersonalVoice()
                }
                .disabled(isRequestingPersonalVoice)
            }
        } label: {
            Image(systemName: "person.wave.2").barGlyph()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Voice and Speed")
        .task { voices = SpeechVoiceCatalog.voices(for: nil) }
    }

    private func label(for value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private func requestPersonalVoice() {
        isRequestingPersonalVoice = true
        Task { @MainActor in
            _ = await SpeechVoiceCatalog.requestPersonalVoiceAccess()
            voices = SpeechVoiceCatalog.voices(for: nil)
            isRequestingPersonalVoice = false
        }
    }
}
