//
//  SharedInboxTests.swift
//  Feed Me, Seymour! Tests
//
//  The queue between the share extension and the app. The crossing itself
//  needs two processes and a provisioned app group; what is tested here is the
//  part that can go wrong on either side of it.
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Shared inbox")
struct SharedInboxTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "inbox.tests.\(UUID().uuidString)")!
    }

    private func pending(_ url: String, _ title: String) -> PendingSubscription {
        PendingSubscription(feedURL: url, title: title, homePageURL: nil, iconURL: nil, addedAt: .now)
    }

    @Test("A subscription waits until the app saves it")
    func addAndRead() {
        let defaults = makeDefaults()
        SharedInbox.add(pending("https://kottke.org/feed", "Kottke"), to: defaults)

        #expect(SharedInbox.pending(in: defaults).map(\.title) == ["Kottke"])
        #expect(SharedInbox.pending(in: defaults).count == 1, "reading does not consume it")
    }

    /// Reading must not empty the queue: if the save throws, the subscription
    /// has to still be there next time.
    @Test("Clearing takes only what was saved")
    func clearsOnlySaved() {
        let defaults = makeDefaults()
        let kottke = pending("https://kottke.org/feed", "Kottke")
        let df = pending("https://daringfireball.net/feeds/main", "Daring Fireball")
        SharedInbox.add(kottke, to: defaults)
        SharedInbox.add(df, to: defaults)

        SharedInbox.clear([kottke], in: defaults)

        #expect(SharedInbox.pending(in: defaults).map(\.title) == ["Daring Fireball"])
    }

    @Test("Sharing the same site twice queues it once")
    func noDuplicates() {
        let defaults = makeDefaults()
        SharedInbox.add(pending("https://kottke.org/feed", "Kottke"), to: defaults)
        SharedInbox.add(pending("https://kottke.org/feed", "Kottke dot org"), to: defaults)

        let waiting = SharedInbox.pending(in: defaults)
        #expect(waiting.count == 1)
        #expect(waiting.first?.title == "Kottke dot org", "the newer title wins")
    }

    @Test("Several different sites all wait their turn")
    func keepsSeveral() {
        let defaults = makeDefaults()
        SharedInbox.add(pending("https://a.example/feed", "A"), to: defaults)
        SharedInbox.add(pending("https://b.example/feed", "B"), to: defaults)
        SharedInbox.add(pending("https://c.example/feed", "C"), to: defaults)

        #expect(SharedInbox.pending(in: defaults).map(\.title) == ["A", "B", "C"])
    }

    @Test("Nothing waiting reads as nothing")
    func empty() {
        #expect(SharedInbox.pending(in: makeDefaults()).isEmpty)
    }
}
