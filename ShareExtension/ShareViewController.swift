//
//  ShareViewController.swift
//  Feed Me, Seymour! — Share Extension
//
//  Share a page from Safari and it becomes a subscription. The extension does
//  the smallest possible amount of work: it pulls the address out of whatever
//  was shared and leaves it where the app will find it. Finding the feed behind
//  a site, and saving it, stay in the app, which already knows how.
//
//  It goes through a shared app group rather than opening the app directly.
//  `extensionContext.open` is sanctioned for only a couple of extension kinds,
//  and from a share extension it fails without saying so — the sheet dismisses,
//  the app never launches, and nothing has happened. A handed-over address in
//  the group survives that, and the app picks it up the moment it is next in
//  front of you.
//

import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias ShareHostController = UIViewController
#else
import AppKit
typealias ShareHostController = NSViewController
#endif

final class ShareViewController: ShareHostController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handOff() }
    }

    #if os(macOS)
    override func loadView() {
        // A share extension on the Mac must have a view even when it never
        // shows one; without it the host has nothing to present and the
        // extension is torn down before `viewDidLoad` runs.
        view = NSView(frame: .zero)
    }
    #endif

    private func handOff() async {
        if let url = await sharedURL() {
            SharedInbox.hand(over: url)
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
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
