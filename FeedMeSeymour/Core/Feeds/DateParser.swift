//
//  DateParser.swift
//  Feed Me, Seymour!
//
//  Feeds date their entries in a dozen dialects. Try them all, cheapest first.
//

import Foundation

enum DateParser {
    nonisolated(unsafe) private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Formats seen in the wild, in rough order of how often they turn up.
    private static let patterns: [String] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",      // RFC 822, the RSS house style
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm Z",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss Z",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm:ss",
        "EEE MMM dd HH:mm:ss Z yyyy"        // asctime-ish, seen in older Blogger exports
    ]

    nonisolated(unsafe) private static let formatters: [DateFormatter] = patterns.map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter
    }

    static func date(from raw: String?) -> Date? {
        guard var text = raw?.trimmed, !text.isEmpty else { return nil }

        // Some feeds write "GMT+00:00" or use a named zone the POSIX locale rejects.
        text = text.replacingOccurrences(of: "GMT+00:00", with: "+0000")
        if text.hasSuffix("UT") { text = String(text.dropLast(2)) + "GMT" }

        if let date = iso8601WithFraction.date(from: text) { return date }
        if let date = iso8601.date(from: text) { return date }
        for formatter in formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// `itunes:duration` is "1:02:03", "62:03" or a bare second count.
    static func duration(from raw: String?) -> TimeInterval? {
        guard let text = raw?.trimmed, !text.isEmpty else { return nil }
        if !text.contains(":") { return TimeInterval(text) }
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
