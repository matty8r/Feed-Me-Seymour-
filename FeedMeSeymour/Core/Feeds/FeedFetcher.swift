//
//  FeedFetcher.swift
//  Feed Me, Seymour!
//

import Foundation

struct FeedFetchResult: Sendable {
    var feed: ParsedFeed
    var etag: String?
    var lastModified: String?
    var resolvedURL: URL
}

enum FeedFetchOutcome: Sendable {
    case notModified
    case fetched(FeedFetchResult)
}

enum FeedFetchError: LocalizedError {
    case badStatus(Int)
    case notAFeed

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            "The server answered \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))."
        case .notAFeed:
            "Nothing at that address looked like a feed."
        }
    }
}

actor FeedFetcher {
    static let shared = FeedFetcher()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            configuration.httpAdditionalHeaders = [
                "User-Agent": Self.userAgent,
                "Accept": "application/atom+xml, application/rss+xml, application/feed+json, application/json;q=0.9, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5"
            ]
            configuration.timeoutIntervalForRequest = 30
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return "FeedMeSeymour/\(version) (\(platform); +https://github.com/matty8r/Feed-Me-Seymour-)"
    }

    func fetch(url: URL, etag: String? = nil, lastModified: String? = nil) async throws -> FeedFetchOutcome {
        var request = URLRequest(url: url)
        // Conditional GET: a quiet feed should cost one 304 and no parsing.
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            let feed = try FeedParser.parse(data: data, sourceURL: url)
            return .fetched(FeedFetchResult(feed: feed, etag: nil, lastModified: nil, resolvedURL: url))
        }

        if http.statusCode == 304 { return .notModified }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedFetchError.badStatus(http.statusCode)
        }

        let mimeType = http.value(forHTTPHeaderField: "Content-Type")
        let resolved = http.url ?? url
        let feed = try FeedParser.parse(data: data, mimeType: mimeType, sourceURL: resolved)

        return .fetched(
            FeedFetchResult(
                feed: feed,
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                resolvedURL: resolved
            )
        )
    }

    /// Raw bytes, for feed discovery inside an HTML page.
    func data(from url: URL) async throws -> (Data, HTTPURLResponse?) {
        let (data, response) = try await session.data(from: url)
        return (data, response as? HTTPURLResponse)
    }
}
