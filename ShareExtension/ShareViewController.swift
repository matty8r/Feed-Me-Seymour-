//
//  ShareViewController.swift
//  Feed Me, Seymour! — Share Extension
//
//  Share a page and subscribe to it without leaving what you were reading.
//
//  On iOS the extension does the work: it resolves the site to an actual feed
//  over the network — the same discovery the app uses, compiled in here too —
//  shows what it found, and takes the subscription on. Writing the row is left
//  to the app, which is the only side that opens the library, but that is
//  bookkeeping: by the time the sheet says "Subscribed" the decision is made
//  and recorded where it cannot be lost.
//
//  On the Mac none of this is needed. An extension there may open its own app,
//  so it does, and the app's own Add sheet takes over — which is better than a
//  panel inside the share menu, and keeps the Mac build free of the app group
//  and the provisioning that would come with it.
//

import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
import SwiftUI

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let panel = SharePanel(
            load: { [weak self] in await self?.sharedURL() ?? nil },
            done: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        )

        let host = UIHostingController(rootView: panel)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
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

#else

import AppKit

final class ShareViewController: NSViewController {

    override func loadView() {
        // A share extension on the Mac must have a view even when it never
        // shows one; without it the host has nothing to present and the
        // extension is torn down before `viewDidLoad` runs.
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handOff() }
    }

    private func handOff() async {
        if let url = await sharedURL() {
            var components = URLComponents()
            components.scheme = "feedmeseymour"
            components.host = "add"
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            if let destination = components.url {
                NSWorkspace.shared.open(destination)
            }
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

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
#endif
