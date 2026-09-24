//
//  SharedInbox.swift
//  Feed Me, Seymour!
//
//  The one thing the share extension and the app both touch: an address handed
//  from one to the other. Compiled into both.
//
//  A single value rather than a queue. Sharing two pages before opening the app
//  is not a thing anyone does on purpose, and a queue would need the app to
//  present a sheet per entry; the newer address simply wins.
//

import Foundation

enum SharedInbox {

    /// Both targets carry this in their entitlements.
    static let appGroup = "group.com.backyard.feedmeseymour"

    static let key = "sharedSubscriptionURL"
    static let stampKey = "sharedSubscriptionDate"

    /// Anything older than this was shared in a session the reader has long
    /// since forgotten about, and springing a sheet on them for it would be a
    /// surprise rather than a convenience.
    private static let freshness: TimeInterval = 5 * 60

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func hand(over url: URL) {
        guard let defaults else { return }
        hand(over: url, into: defaults)
    }

    static func hand(over url: URL, into defaults: UserDefaults) {
        defaults.set(url.absoluteString, forKey: key)
        defaults.set(Date.now.timeIntervalSince1970, forKey: stampKey)
    }

    /// Reads and clears. Returns nil when there is nothing waiting, or when
    /// what is waiting has gone stale.
    static func collect() -> String? {
        guard let defaults else { return nil }
        return collect(from: defaults)
    }

    static func collect(from defaults: UserDefaults) -> String? {
        guard let address = defaults.string(forKey: key) else { return nil }
        let stamp = defaults.double(forKey: stampKey)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: stampKey)

        guard stamp > 0, Date.now.timeIntervalSince1970 - stamp < freshness else { return nil }
        return address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address
    }
}
