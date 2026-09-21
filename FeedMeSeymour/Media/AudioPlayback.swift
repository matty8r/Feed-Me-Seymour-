//
//  AudioPlayback.swift
//  Feed Me, Seymour!
//
//  One audio player for the whole app, wired into the system's Now Playing
//  controls so a podcast enclosure behaves like a podcast: Control Center,
//  the Lock Screen, AirPods pinches and media keys all work.
//

import Foundation
import AVFoundation
import MediaPlayer
import Observation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class AudioPlaybackController {

    static let shared = AudioPlaybackController()

    private(set) var currentURL: URL?
    private(set) var currentTitle: String?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    var currentTime: Double = 0
    var duration: Double = 0
    var rate: Float = 1.0 {
        didSet {
            guard isPlaying else { return }
            player?.rate = rate
            updateNowPlaying()
        }
    }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var hasConfiguredRemoteCommands = false

    private init() {}

    // MARK: - Transport

    func isCurrent(_ media: AudioMedia) -> Bool { currentURL == media.url }

    func toggle(_ media: AudioMedia, artworkURL: URL? = nil, feedTitle: String? = nil) {
        if isCurrent(media) {
            isPlaying ? pause() : resume()
        } else {
            start(media, artworkURL: artworkURL, feedTitle: feedTitle)
        }
    }

    func start(_ media: AudioMedia, artworkURL: URL? = nil, feedTitle: String? = nil) {
        teardown()
        configureSession()
        configureRemoteCommands()

        let item = AVPlayerItem(url: media.url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        currentURL = media.url
        currentTitle = media.title ?? feedTitle ?? media.url.lastPathComponent
        duration = media.duration ?? 0
        currentTime = 0
        isLoading = true

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                    self.isLoading = false
                }
                self.updateNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish()
            }
        }

        player.rate = rate
        isPlaying = true
        loadArtwork(artworkURL ?? media.artworkURL)
        updateNowPlaying()
    }

    func resume() {
        guard let player else { return }
        configureSession()
        player.rate = rate
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        teardown()
        currentURL = nil
        currentTitle = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateNowPlaying()
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func finish() {
        isPlaying = false
        currentTime = duration
        updateNowPlaying()
    }

    private func teardown() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }

    // MARK: - System integration

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
    }

    private func configureRemoteCommands() {
        guard !hasConfiguredRemoteCommands else { return }
        hasConfiguredRemoteCommands = true

        // Command handlers arrive on an unspecified queue, so hop deliberately.
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying ? self.pause() : self.resume()
            }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 30) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = currentTitle ?? "Audio"
        info[MPMediaItemPropertyArtist] = "Feed Me, Seymour!"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ url: URL?) {
        guard let url else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = PlatformImage(data: data) else { return }
            await MainActor.run {
                guard self != nil else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}

extension Double {
    /// `1:04:12` / `4:12`, the way a transport control should read.
    var playbackTimestamp: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let total = Int(rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
