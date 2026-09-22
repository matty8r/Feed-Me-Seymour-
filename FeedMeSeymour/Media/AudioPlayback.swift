//
//  AudioPlayback.swift
//  Feed Me, Seymour!
//
//  One audio player for the whole app, so a podcast enclosure behaves like a
//  podcast. The Lock Screen, Control Center, media keys and AirPods are
//  arbitrated by `NowPlayingCenter`, which this shares with the speech reader —
//  only one of them can own the transport at a time.
//

import Foundation
import AVFoundation
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
            publishProgress()
        }
    }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

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
        AudioSession.activatePlayback()

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
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                    self.isLoading = false
                }
                self.publishProgress()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }

        player.rate = rate
        isPlaying = true

        NowPlayingCenter.shared.activate(
            self,
            title: currentTitle ?? "Audio",
            artist: feedTitle,
            artworkURL: artworkURL ?? media.artworkURL
        )
        publishProgress()
    }

    func resume() {
        guard let player else { return }
        AudioSession.activatePlayback()
        player.rate = rate
        isPlaying = true
        if NowPlayingCenter.shared.activeSource !== self {
            NowPlayingCenter.shared.activate(self, title: currentTitle ?? "Audio", artist: nil)
        }
        publishProgress()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        publishProgress()
    }

    func stop() {
        teardown()
        currentURL = nil
        currentTitle = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        NowPlayingCenter.shared.resign(self)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        publishProgress()
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func finish() {
        isPlaying = false
        currentTime = duration
        publishProgress()
    }

    private func teardown() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }

    private func publishProgress() {
        NowPlayingCenter.shared.update(
            elapsed: currentTime,
            duration: duration > 0 ? duration : nil,
            rate: isPlaying ? Double(rate) : 0,
            for: self
        )
    }
}

// MARK: - Now Playing

extension AudioPlaybackController: NowPlayingSource {
    var nowPlayingIsPlaying: Bool { isPlaying }
    var nowPlayingSupportsSeeking: Bool { true }

    func nowPlayingPlay() { resume() }
    func nowPlayingPause() { pause() }
    func nowPlayingNext() { skip(by: 30) }
    func nowPlayingPrevious() { skip(by: -15) }
    func nowPlayingSeek(to seconds: Double) { seek(to: seconds) }
    func nowPlayingWasSuperseded() { pause() }
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
