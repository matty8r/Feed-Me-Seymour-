//
//  MediaAttachment.swift
//  Feed Me, Seymour!
//
//  Enclosures: podcast audio, video, images and everything else a feed hangs
//  off an item. Each one gets real playback controls in the reader.
//

import Foundation
import SwiftData

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
