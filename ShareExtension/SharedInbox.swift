//
//  SharedInbox.swift
//  Feed Me, Seymour!
//
//  What the share extension and the app both touch: subscriptions the
//  extension has taken on, waiting for the app to write them into the library.
//  Compiled into both.
//
//  The extension does the finding — it resolves the site to an actual feed
//  over the network and confirms it on the spot — but it cannot write to the
//  library, which is a SwiftData store the app alone opens. So it records what
//  it settled on, and the app materialises it the next time it runs. From the
//  reader's side the subscription is made the moment the sheet says so; all
//  that is outstanding is a row.
//

import Foundation

/// A subscription the extension resolved and the reader accepted.
struct PendingSubscription: Codable, Equatable, Sendable {
    var feedURL: String
    var title: String
    var homePageURL: String?
    var iconURL: String?
    var addedAt: Date
}

enum SharedInbox {

    /// Both targets carry this in their iOS entitlements.
    static let appGroup = "group.com.backyard.feedmeseymour"

    static let key = "pendingSubscriptions"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func add(_ subscription: PendingSubscription) {
        guard let defaults else { return }
        add(subscription, to: defaults)
    }

    static func add(_ subscription: PendingSubscription, to defaults: UserDefaults) {
        var waiting = pending(in: defaults)
        // Sharing the same site twice should not queue it twice.
        waiting.removeAll { $0.feedURL == subscription.feedURL }
        waiting.append(subscription)
        write(waiting, to: defaults)
    }

    /// Everything waiting, oldest first. Reads without clearing, so a failure
    /// to write them into the library does not lose them.
    static func pending(in defaults: UserDefaults? = SharedInbox.defaults) -> [PendingSubscription] {
        guard let defaults, let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingSubscription].self, from: data)) ?? []
    }

    /// Called once the app has actually saved them.
    static func clear(_ saved: [PendingSubscription], in defaults: UserDefaults? = SharedInbox.defaults) {
        guard let defaults else { return }
        let savedURLs = Set(saved.map(\.feedURL))
        write(pending(in: defaults).filter { !savedURLs.contains($0.feedURL) }, to: defaults)
    }

    private static func write(_ list: [PendingSubscription], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
