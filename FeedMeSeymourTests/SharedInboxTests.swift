//
//  SharedInboxTests.swift
//  Feed Me, Seymour! Tests
//
//  The handover between the share extension and the app. The crossing itself
//  needs two processes and a provisioned app group, so what is tested here is
//  the part that can go wrong on either side of it: that an address survives
//  the trip once, and only once, and does not turn up days later.
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Shared inbox")
struct SharedInboxTests {

    /// The real suite is the app group, which tests cannot reach. The rules
    /// are the same either way.
    private func makeDefaults() -> UserDefaults {
        let suite = "inbox.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("An address handed over is collected once")
    func handOverAndCollect() {
        let defaults = makeDefaults()
        SharedInbox.hand(over: URL(string: "https://kottke.org")!, into: defaults)

        #expect(SharedInbox.collect(from: defaults) == "https://kottke.org")
        #expect(SharedInbox.collect(from: defaults) == nil, "collecting empties it")
    }

    @Test("Nothing waiting collects nothing")
    func emptyInbox() {
        #expect(SharedInbox.collect(from: makeDefaults()) == nil)
    }

    /// Shared last Tuesday and never opened. Springing a sheet for it now
    /// would be a surprise rather than a convenience.
    @Test("A stale address is dropped rather than acted on")
    func staleAddress() {
        let defaults = makeDefaults()
        SharedInbox.hand(over: URL(string: "https://kottke.org")!, into: defaults)
        defaults.set(Date.now.timeIntervalSince1970 - 3600, forKey: SharedInbox.stampKey)

        #expect(SharedInbox.collect(from: defaults) == nil)
    }

    @Test("A stale address is still cleared out")
    func staleAddressIsCleared() {
        let defaults = makeDefaults()
        SharedInbox.hand(over: URL(string: "https://kottke.org")!, into: defaults)
        defaults.set(Date.now.timeIntervalSince1970 - 3600, forKey: SharedInbox.stampKey)

        _ = SharedInbox.collect(from: defaults)
        #expect(defaults.string(forKey: SharedInbox.key) == nil)
    }

    @Test("The newer of two shares wins")
    func newerWins() {
        let defaults = makeDefaults()
        SharedInbox.hand(over: URL(string: "https://kottke.org")!, into: defaults)
        SharedInbox.hand(over: URL(string: "https://daringfireball.net")!, into: defaults)

        #expect(SharedInbox.collect(from: defaults) == "https://daringfireball.net")
    }
}
