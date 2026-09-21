//
//  Article.swift
//  Feed Me, Seymour!
//

import Foundation
import SwiftData

@Model
final class Article {
    var uuid: UUID = UUID()

    /// Identity *within a feed*: `<guid>`, Atom `<id>`, or the permalink as a last resort.
    var guid: String = ""

    var title: String = ""
    var url: URL?
    var externalURLString: String?

    var author: String?

    /// The short form from `<description>` / `<summary>`, still HTML.
    var summaryHTML: String?

    /// The long form from `<content:encoded>` / Atom `<content>`, still HTML.
    var contentHTML: String?

    /// Plain-text dek, derived once at insert time so list rows never parse HTML.
    var plainSummary: String = ""

    var publishedAt: Date = Date.distantPast
    var updatedAt: Date?
    var dateFetched: Date = Date()

    var isRead: Bool = false
    var isStarred: Bool = false
    var starredAt: Date?

    /// Clock for `isRead` / `isStarred`, compared against the iCloud mirror.
    var stateUpdatedAt: Date = Date.distantPast

    /// A favourite that arrived from another device before its body did. The
    /// next refresh of this feed fills it in.
    var isPlaceholder: Bool = false

    var bannerImageURL: URL?
    var wordCount: Int = 0

    /// Tags/categories the publisher attached.
    var tags: [String] = []

    var feed: Feed?

    @Relationship(deleteRule: .cascade, inverse: \MediaAttachment.article)
    var attachments: [MediaAttachment] = []

    init(
        guid: String,
        title: String,
        url: URL? = nil,
        author: String? = nil,
        summaryHTML: String? = nil,
        contentHTML: String? = nil,
        plainSummary: String = "",
        publishedAt: Date,
        updatedAt: Date? = nil,
        bannerImageURL: URL? = nil,
        wordCount: Int = 0,
        tags: [String] = []
    ) {
        self.uuid = UUID()
        self.guid = guid
        self.title = title
        self.url = url
        self.externalURLString = url?.absoluteString
        self.author = author
        self.summaryHTML = summaryHTML
        self.contentHTML = contentHTML
        self.plainSummary = plainSummary
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.dateFetched = Date()
        self.bannerImageURL = bannerImageURL
        self.wordCount = wordCount
        self.tags = tags
    }

    /// The richest HTML we have for this article.
    var bestHTML: String? {
        if let contentHTML, contentHTML.trimmed.count > (summaryHTML?.trimmed.count ?? 0) {
            return contentHTML
        }
        return contentHTML ?? summaryHTML
    }

    var displayTitle: String {
        title.trimmed.isEmpty ? "Untitled" : title.trimmed
    }

    /// Reading time at a deliberately unhurried 200 wpm.
    var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 200.0).rounded()))
    }

    var hasAudio: Bool { attachments.contains { $0.kind == .audio } }
    var hasVideo: Bool { attachments.contains { $0.kind == .video } }

    func toggleStar() {
        isStarred.toggle()
        starredAt = isStarred ? Date() : nil
        stateUpdatedAt = .now
    }

    /// How a *person's* action should change read state: bumping the clock is
    /// what lets iCloud tell which device knows best. The sync coordinator
    /// assigns `isRead` directly when it is adopting another device's clock.
    func setRead(_ value: Bool) {
        guard isRead != value else { return }
        isRead = value
        stateUpdatedAt = .now
    }
}
