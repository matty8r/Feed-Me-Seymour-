//
//  AnimatedImageView.swift
//  Feed Me, Seymour!
//
//  Animated GIFs and APNGs, decoded with ImageIO and driven by TimelineView.
//  No web view, no third-party dependency, correct frame timing.
//

import SwiftUI
import ImageIO

struct AnimatedImageFrame {
    var image: CGImage
    var duration: Double
    /// Cumulative end time, so lookup is a single scan.
    var endTime: Double
}

struct AnimatedImageView: View {

    let url: URL
    var contentMode: ContentMode = .fill

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [AnimatedImageFrame] = []
    @State private var totalDuration: Double = 0
    @State private var failed = false
    @State private var isPaused = false

    var body: some View {
        content
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if failed {
            ZStack {
                palette.codeBackground
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(palette.tertiaryInk)
            }
        } else if frames.isEmpty {
            ZStack {
                palette.codeBackground
                ProgressView().controlSize(.small)
            }
        } else if frames.count == 1 || totalDuration <= 0 {
            still(frames[0].image)
        } else if reduceMotion || isPaused {
            // Reduce Motion means a still with an explicit way to start it.
            still(frames[0].image)
                .overlay(alignment: .bottomLeading) { playBadge }
                .onTapGesture { isPaused = false }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                if let frame = frame(at: context.date) {
                    still(frame.image)
                } else {
                    Color.clear
                }
            }
            .overlay(alignment: .bottomLeading) { gifBadge }
            .onTapGesture { isPaused = true }
        }
    }

    private func still(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }

    private var gifBadge: some View {
        Text("GIF")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(8)
            .allowsHitTesting(false)
    }

    private var playBadge: some View {
        Label("GIF", systemImage: "play.fill")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(8)
            .allowsHitTesting(false)
    }

    private func frame(at date: Date) -> AnimatedImageFrame? {
        guard totalDuration > 0, let last = frames.last else { return frames.first }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        for frame in frames where elapsed < frame.endTime {
            return frame
        }
        return last
    }

    private func load() async {
        guard frames.isEmpty else { return }
        let decoded = await AnimatedImageDecoder.decode(url: url)
        await MainActor.run {
            if decoded.isEmpty {
                failed = true
            } else {
                frames = decoded
                totalDuration = decoded.last?.endTime ?? 0
            }
        }
    }
}

enum AnimatedImageDecoder {

    /// Animations longer than this are trimmed rather than held in memory whole.
    static let frameLimit = 240

    static func decode(url: URL) async -> [AnimatedImageFrame] {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return decode(data: data)
    }

    static func decode(data: Data) -> [AnimatedImageFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = min(CGImageSourceGetCount(source), frameLimit)
        guard count > 0 else { return [] }

        var frames: [AnimatedImageFrame] = []
        frames.reserveCapacity(count)
        var elapsed: Double = 0

        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let duration = frameDuration(source: source, index: index)
            elapsed += duration
            frames.append(AnimatedImageFrame(image: image, duration: duration, endTime: elapsed))
        }
        return frames
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }

        func delay(in dictionary: [CFString: Any]?, unclamped: CFString, clamped: CFString) -> Double? {
            guard let dictionary else { return nil }
            if let value = dictionary[unclamped] as? Double, value > 0 { return value }
            if let value = dictionary[clamped] as? Double, value > 0 { return value }
            return nil
        }

        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        if let value = delay(in: gif, unclamped: kCGImagePropertyGIFUnclampedDelayTime, clamped: kCGImagePropertyGIFDelayTime) {
            // Browsers clamp anything under 20ms to 100ms; match that so timing looks right.
            return value < 0.02 ? 0.1 : value
        }

        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        if let value = delay(in: png, unclamped: kCGImagePropertyAPNGUnclampedDelayTime, clamped: kCGImagePropertyAPNGDelayTime) {
            return value < 0.02 ? 0.1 : value
        }

        let heics = properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any]
        if let value = delay(in: heics, unclamped: kCGImagePropertyHEICSUnclampedDelayTime, clamped: kCGImagePropertyHEICSDelayTime) {
            return value < 0.02 ? 0.1 : value
        }

        return 0.1
    }
}
