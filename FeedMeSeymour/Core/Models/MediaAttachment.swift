//
//  MediaAttachment.swift
//  Feed Me, Seymour!
//
//  Enclosures: podcast audio, video, images and everything else a feed hangs
//  off an item. Each one gets real playback controls in the reader.
//

import Foundation
import SwiftData
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

@Model
final class MediaAttachment {
    var uuid: UUID = UUID()
    var url: URL = URL(string: "https://example.com")!
    var mimeType: String?
    var title: String?
    var durationSeconds: Double?
    var byteCount: Int?
    var kindRawValue: String = MediaKind.document.rawValue
    var article: Article?

    init(url: URL, mimeType: String? = nil, title: String? = nil, durationSeconds: Double? = nil, byteCount: Int? = nil) {
        self.uuid = UUID()
        self.url = url
        self.mimeType = mimeType
        self.title = title
        self.durationSeconds = durationSeconds
        self.byteCount = byteCount
        self.kindRawValue = MediaKind.inferred(mimeType: mimeType, url: url).rawValue
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRawValue) ?? .document }
        set { kindRawValue = newValue.rawValue }
    }

    var formattedDuration: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return Duration.seconds(durationSeconds).formatted(
            .time(pattern: durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    var formattedSize: String? {
        guard let byteCount, byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
