//
//  ShareViewController.swift
//  Feed Me, Seymour! — Share Extension
//
//  Share a page and subscribe to it without leaving what you were reading.
//
//  Both platforms show the same panel and do the same work: resolve the site
//  to an actual feed over the network — the app's own discovery, compiled in
//  here too — show what was found, and take the subscription on a tap.
//
//  Only the last step differs. iOS records it in a shared app group for the
//  app to write in, because an extension there cannot open its own app. The
//  Mac can, so it hands the resolved feed straight over and the app saves it
//  while you watch.
//
//  An earlier version of the Mac side did the work with no interface at all,
//  called NSWorkspace.open and completed the request on the next line. Neither
//  half of that survives: a share extension with a zero-sized view is torn
//  down by the host before its work finishes, and completing the request kills
//  the process while the launch is still being dispatched. It looked exactly
//  like nothing happening.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias ShareHostController = UIViewController
typealias ShareHostingController = UIHostingController
#else
import AppKit
typealias ShareHostController = NSViewController
typealias ShareHostingController = NSHostingController
#endif

final class ShareViewController: ShareHostController {

    #if os(macOS)
    override func loadView() {
        // Big enough that the host actually presents it and keeps this process
        // alive while the feed is being looked up.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 220))
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()

        let panel = SharePanel(
            load: { [weak self] in await self?.sharedURL() ?? nil },
            subscribe: { [weak self] feed in self?.subscribe(to: feed) },
            isWaiting: { feed in
                #if os(iOS)
                SharedInbox.pending().contains { $0.feedURL == feed.url.absoluteString }
                #else
                false
                #endif
            },
            done: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        )

        let host = ShareHostingController(rootView: panel)
        addChild(host)
        #if os(iOS)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        #else
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
        #endif
    }

    private func subscribe(to feed: DiscoveredFeed) {
        #if os(iOS)
        SharedInbox.add(
            PendingSubscription(
                feedURL: feed.url.absoluteString,
                title: feed.title,
                homePageURL: feed.homePageURL?.absoluteString,
                iconURL: feed.iconURL?.absoluteString,
                addedAt: .now
            )
        )
        #else
        var components = URLComponents()
        components.scheme = "feedmeseymour"
        components.host = "subscribe"
        components.queryItems = [
            URLQueryItem(name: "url", value: feed.url.absoluteString),
            URLQueryItem(name: "title", value: feed.title),
            URLQueryItem(name: "home", value: feed.homePageURL?.absoluteString),
            URLQueryItem(name: "icon", value: feed.iconURL?.absoluteString)
        ]
        guard let destination = components.url else { return }
        // The app is opened before this process goes away, not alongside it.
        NSWorkspace.shared.open(destination)
        #endif
    }

    /// Safari offers a page as a URL; other hosts sometimes offer only the
    /// text of one. Take either.
    private func sharedURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return url
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return url
                }
            }
        }
        return nil
    }
}
