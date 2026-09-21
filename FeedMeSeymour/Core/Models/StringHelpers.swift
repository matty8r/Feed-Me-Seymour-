//
//  StringHelpers.swift
//  Feed Me, Seymour!
//

import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? { trimmed.isEmpty ? nil : self }

    /// Collapses runs of whitespace so summaries pulled out of HTML read like one line.
    var squeezedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func truncated(to limit: Int) -> String {
        guard count > limit else { return self }
        let cut = index(startIndex, offsetBy: limit)
        // Prefer breaking on a word boundary.
        if let space = self[..<cut].lastIndex(where: { $0 == " " }) {
            return String(self[..<space]) + "…"
        }
        return String(self[..<cut]) + "…"
    }

    var wordCount: Int {
        var count = 0
        enumerateSubstrings(in: startIndex..<endIndex, options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

extension URL {
    /// `theverge.com` rather than `www.theverge.com` — what a person would say out loud.
    var prettyHost: String {
        guard let host = host() else { return absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Resolves a possibly-relative href found inside article HTML.
    static func resolving(_ candidate: String, relativeTo base: URL?) -> URL? {
        let trimmed = candidate.trimmed
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            let scheme = base?.scheme ?? "https"
            return URL(string: "\(scheme):\(trimmed)")
        }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}

extension Date {
    /// "3:12 PM" today, "Tuesday" this week, "Mar 4" this year, "Mar 4, 2023" before that.
    var timelineStamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return "Yesterday"
        }
        if let week = calendar.date(byAdding: .day, value: -6, to: .now), self > week {
            return formatted(.dateTime.weekday(.wide))
        }
        if calendar.component(.year, from: self) == calendar.component(.year, from: .now) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }

    var readerStamp: String {
        formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var relativeStamp: String {
        let style = RelativeDateTimeFormatter()
        style.unitsStyle = .abbreviated
        return style.localizedString(for: self, relativeTo: .now)
    }
}
