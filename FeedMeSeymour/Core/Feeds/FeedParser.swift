//
//  FeedParser.swift
//  Feed Me, Seymour!
//
//  Sniffs the payload and hands it to whichever parser can read it.
//

import Foundation

enum FeedParser {

    static func parse(data: Data, mimeType: String? = nil, sourceURL: URL? = nil) throws -> ParsedFeed {
        guard !data.isEmpty else { throw FeedParseError.empty }

        let looksLikeJSON = (mimeType?.localizedCaseInsensitiveContains("json") ?? false)
            || firstNonWhitespaceByte(of: data) == UInt8(ascii: "{")

        if looksLikeJSON {
            // A misdeclared content type shouldn't cost us the feed.
            if let feed = try? JSONFeedParser.parse(data: data, sourceURL: sourceURL) { return feed }
        }

        let normalized = normalizedXMLData(data)
        do {
            return try XMLFeedParser().parse(data: normalized, sourceURL: sourceURL)
        } catch {
            if !looksLikeJSON, let feed = try? JSONFeedParser.parse(data: data, sourceURL: sourceURL) {
                return feed
            }
            throw error
        }
    }

    private static func firstNonWhitespaceByte(of data: Data) -> UInt8? {
        for byte in data.prefix(64) where !(byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0xEF || byte == 0xBB || byte == 0xBF) {
            return byte
        }
        return nil
    }

    /// `XMLParser` refuses documents with a leading BOM or stray whitespace before
    /// the prolog, which a surprising number of feeds ship.
    private static func normalizedXMLData(_ data: Data) -> Data {
        guard let start = data.firstIndex(of: UInt8(ascii: "<")), start > data.startIndex else { return data }
        return data.subdata(in: start..<data.endIndex)
    }
}
