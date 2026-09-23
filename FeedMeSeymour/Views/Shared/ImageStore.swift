//
//  ImageStore.swift
//  Feed Me, Seymour!
//
//  A decoded-image cache.
//
//  `AsyncImage` keeps nothing in memory: every time one is created it starts
//  again, and decoding a photograph is far more expensive than fetching it from
//  the URL cache. That is invisible until views get rebuilt often — scrolling a
//  timeline of thumbnails, or moving between articles, where the reader's whole
//  body is replaced each time. Then the same handful of pictures are decoded
//  over and over.
//
//  Holding the decoded images means a picture is paid for once.
//

import SwiftUI

@MainActor
final class ImageStore {

    static let shared = ImageStore()

    private let cache = NSCache<NSURL, PlatformImage>()
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    init() {
        cache.countLimit = 240
        // Roughly 120MB of decoded pixels before the oldest start going.
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    /// Already decoded, so a view can show it on its first pass with no flash
    /// of placeholder and no animation back in.
    func cached(_ url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> PlatformImage? {
        if let cached = cached(url) { return cached }

        // Several rows can ask for the same picture at once — a feed's own
        // logo, or the same story syndicated twice. Fetch it once.
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<PlatformImage?, Never> { [weak self] in
            defer { Task { @MainActor in self?.inFlight[url] = nil } }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = PlatformImage(data: data)
            else { return nil }
            await MainActor.run { self?.store(image, for: url) }
            return image
        }
        inFlight[url] = task
        return await task.value
    }

    private func store(_ image: PlatformImage, for url: URL) {
        let size = image.size
        let cost = Int(size.width * size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: max(cost, 1))
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
