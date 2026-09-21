//
//  AudioPlayerCard.swift
//  Feed Me, Seymour!
//
//  Inline transport for an audio enclosure. Scrubbing, skip, speed and AirPlay,
//  backed by the shared controller so only one thing ever plays at a time.
//

import SwiftUI
import AVKit

struct AudioPlayerCard: View {

    let media: AudioMedia
    var subtitle: String?

    @Environment(\.palette) private var palette
    @State private var scrubValue: Double?

    private var controller: AudioPlaybackController { .shared }

    private var isCurrent: Bool { controller.isCurrent(media) }
    private var isPlaying: Bool { isCurrent && controller.isPlaying }
    private var duration: Double { isCurrent && controller.duration > 0 ? controller.duration : (media.duration ?? 0) }
    private var position: Double { scrubValue ?? (isCurrent ? controller.currentTime : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            transport
            scrubber
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.codeBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.rule, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(media.title ?? "Audio")
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.accent.opacity(0.14))
                if let artworkURL = media.artworkURL {
                    RemoteImage(url: artworkURL, contentMode: .fill, cornerRadius: 10)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(media.title ?? "Audio")
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            ShareLink(item: media.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
            .buttonStyle(.plain)
            .help("Share Audio")
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Button { controller.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 19, weight: .regular))
            }
            .buttonStyle(.plain)
            .disabled(!isCurrent)
            .help("Back 15 seconds")

            Button { controller.toggle(media, feedTitle: subtitle) } label: {
                ZStack {
                    Circle().fill(palette.accent)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: isPlaying ? 0 : 1.5)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            Button { controller.skip(by: 30) } label: {
                Image(systemName: "goforward.30").font(.system(size: 19, weight: .regular))
            }
            .buttonStyle(.plain)
            .disabled(!isCurrent)
            .help("Forward 30 seconds")

            Spacer(minLength: 0)

            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                    Button {
                        controller.rate = Float(value)
                    } label: {
                        if Double(controller.rate) == value {
                            Label(speedLabel(value), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(value))
                        }
                    }
                }
            } label: {
                Text(speedLabel(Double(controller.rate)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(palette.rule))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Playback Speed")

            #if os(iOS)
            AirPlayButton()
                .frame(width: 30, height: 30)
            #endif
        }
        .foregroundStyle(palette.ink)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { position },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if !editing, let value = scrubValue {
                        controller.seek(to: value)
                        scrubValue = nil
                    }
                }
            )
            .tint(palette.accent)
            .disabled(!isCurrent || duration <= 0)

            HStack {
                Text(position.playbackTimestamp)
                Spacer()
                Text(duration > 0 ? "−" + max(duration - position, 0).playbackTimestamp : "--:--")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.tertiaryInk)
        }
    }

    private func speedLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

#if os(iOS)
/// The system AirPlay picker. There is no SwiftUI equivalent.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.activeTintColor = UIColor.systemGreen
        view.tintColor = UIColor.secondaryLabel
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
