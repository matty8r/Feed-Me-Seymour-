//
//  NativeVideoPlayer.swift
//  Feed Me, Seymour!
//
//  AVKit's own player, not SwiftUI's simplified `VideoPlayer`, so readers get
//  the real controls: scrubbing thumbnails, Picture in Picture, AirPlay,
//  subtitles and playback speed.
//

import SwiftUI
import AVKit

#if os(iOS)
import UIKit

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var startsPlaying = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect
        controller.updatesNowPlayingInfoCenter = true
        if startsPlaying { player.play() }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}

#elseif os(macOS)
import AppKit

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var startsPlaying = true

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        if startsPlaying { player.play() }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
    }
}
#endif

/// Holds one `AVPlayer` for the lifetime of a video block, so scrolling past a
/// video and back doesn't restart the download.
final class VideoPlayerBox: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
    }
}
