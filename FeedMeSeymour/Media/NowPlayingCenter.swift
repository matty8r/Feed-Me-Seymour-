//
//  NowPlayingCenter.swift
//  Feed Me, Seymour!
//
//  There is exactly one Lock Screen, one Control Center and one pair of
//  AirPods. A podcast enclosure and an article being read aloud both want
//  them, so neither owns them: whichever started last becomes the active
//  source, and this is the only place that touches `MPNowPlayingInfoCenter`
//  or registers a remote command.
//

import Foundation
import AVFoundation
import MediaPlayer

@MainActor
protocol NowPlayingSource: AnyObject {
    var nowPlayingIsPlaying: Bool { get }

    /// Audio can be scrubbed to a second. Speech is paced by the synthesizer,
    /// so it offers next/previous paragraph instead.
    var nowPlayingSupportsSeeking: Bool { get }

    func nowPlayingPlay()
    func nowPlayingPause()
    func nowPlayingNext()
    func nowPlayingPrevious()
    func nowPlayingSeek(to seconds: Double)

    /// Asked to give up the controls because something else started.
    func nowPlayingWasSuperseded()
}

@MainActor
final class NowPlayingCenter {

    static let shared = NowPlayingCenter()

    private weak var source: (any NowPlayingSource)?
    private var hasRegisteredCommands = false

    private init() {}

    var activeSource: (any NowPlayingSource)? { source }

    // MARK: - Ownership

    func activate(
        _ newSource: any NowPlayingSource,
        title: String,
        artist: String?,
        artworkURL: URL? = nil
    ) {
        if let existing = source, existing !== newSource {
            existing.nowPlayingWasSuperseded()
        }
        source = newSource
        registerCommands()
        configureCommandAvailability(for: newSource)

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist ?? "Feed Me, Seymour!"
        info[MPNowPlayingInfoPropertyPlaybackRate] = newSource.nowPlayingIsPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let artworkURL { loadArtwork(artworkURL) }
    }

    /// Updates the scrubber. Speech passes nothing, so the Lock Screen shows a
    /// live indicator rather than a progress bar built out of guesswork.
    func update(elapsed: Double?, duration: Double?, rate: Double, for caller: any NowPlayingSource) {
        guard source === caller else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if let duration, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func resign(_ caller: any NowPlayingSource) {
        guard source === caller else { return }
        source = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote commands

    private func configureCommandAvailability(for source: any NowPlayingSource) {
        let center = MPRemoteCommandCenter.shared()
        let seeks = source.nowPlayingSupportsSeeking
        center.skipForwardCommand.isEnabled = seeks
        center.skipBackwardCommand.isEnabled = seeks
        center.changePlaybackPositionCommand.isEnabled = seeks
        center.nextTrackCommand.isEnabled = !seeks
        center.previousTrackCommand.isEnabled = !seeks
    }

    private func registerCommands() {
        guard !hasRegisteredCommands else { return }
        hasRegisteredCommands = true

        // Handlers arrive on an unspecified queue, so every one hops deliberately.
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingPlay() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in
                guard let source = NowPlayingCenter.shared.source else { return }
                source.nowPlayingIsPlaying ? source.nowPlayingPause() : source.nowPlayingPlay()
            }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingNext() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingPrevious() }
            return .success
        }

        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in NowPlayingCenter.shared.source?.nowPlayingSeek(to: position) }
            return .success
        }
    }

    private func loadArtwork(_ url: URL) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = PlatformImage(data: data) else { return }
            await MainActor.run {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}

// MARK: - Audio session

enum AudioSession {
    /// Both the podcast player and the speech reader want long-form playback
    /// that survives the screen locking.
    static func activatePlayback() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
    }
}
