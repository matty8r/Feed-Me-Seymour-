//
//  MediaKind.swift
//  Feed Me, Seymour!
//
//  What a piece of media is. Split out from `MediaAttachment` so the feed
//  parsers — which the share extension compiles too — can classify an
//  enclosure without dragging SwiftData and the whole model graph in behind
//  them.
//

import Foundation
import UniformTypeIdentifiers

enum MediaKind: String, Codable, Sendable {
    case audio, video, image, document

    var symbolName: String {
        switch self {
        case .audio: "waveform"
        case .video: "play.rectangle"
        case .image: "photo"
        case .document: "doc"
        }
    }

    static func inferred(mimeType: String?, url: URL?) -> MediaKind {
        if let mimeType = mimeType?.lowercased(), !mimeType.isEmpty {
            if mimeType.hasPrefix("audio/") { return .audio }
            if mimeType.hasPrefix("video/") { return .video }
            if mimeType.hasPrefix("image/") { return .image }
            if let type = UTType(mimeType: mimeType) {
                if type.conforms(to: .audio) { return .audio }
                if type.conforms(to: .movie) { return .video }
                if type.conforms(to: .image) { return .image }
            }
        }
        let ext = (url?.pathExtension ?? "").lowercased()
        switch ext {
        case "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "opus", "oga", "ogg", "caf":
            return .audio
        case "mp4", "m4v", "mov", "webm", "mkv", "avi", "m3u8", "mpd":
            return .video
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tiff", "svg":
            return .image
        default:
            return .document
        }
    }
}
