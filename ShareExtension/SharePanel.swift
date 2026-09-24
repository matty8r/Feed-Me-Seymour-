//
//  SharePanel.swift
//  Feed Me, Seymour! — Share Extension
//
//  The small card that appears over the share sheet: what it found, and a
//  button to take it on. Deliberately the shortest path — one tap, and the
//  sheet closes itself.
//

import SwiftUI

struct SharePanel: View {

    let load: () async -> URL?
    /// What "subscribe" means differs by platform: iOS records it for the app
    /// to write in, the Mac hands it straight to the app, which is running and
    /// can be opened. The panel does not need to know which.
    let subscribe: (DiscoveredFeed) -> Void
    let isWaiting: (DiscoveredFeed) -> Bool
    let done: () -> Void

    private enum Stage: Equatable {
        case looking
        case found(DiscoveredFeed)
        case already(DiscoveredFeed)
        case subscribed(String)
        case nothing(String)
    }

    @State private var stage: Stage = .looking

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(.black.opacity(0.28))
        .ignoresSafeArea()
        .task { await find() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                // The app's own icon rather than a stand-in symbol: this panel
                // appears over somebody else's app, so it has to say whose it is.
                Image("PanelIcon")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("Feed Me, Seymour!")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { done() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: stage)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .looking:
            HStack(spacing: 11) {
                ProgressView().controlSize(.small)
                Text("Looking for a feed…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .found(let feed):
            feedSummary(feed)
            Button {
                take(feed)
            } label: {
                Text("Subscribe")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

        case .already(let feed):
            feedSummary(feed)
            Label("Already subscribed", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

        case .subscribed(let title):
            Label("Subscribed to \(title)", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .nothing(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func feedSummary(_ feed: DiscoveredFeed) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(feed.title)
                .font(.headline)
                .lineLimit(2)
            Text(feed.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Work

    private func find() async {
        guard let url = await load() else {
            stage = .nothing("Nothing here looked like a web page.")
            return
        }

        let results = await FeedDiscovery.discover(from: url.absoluteString)
        guard let best = results.first else {
            stage = .nothing("No feed at \(url.host() ?? url.absoluteString). Some sites don't publish one.")
            return
        }

        // Waiting already, from an earlier share.
        if isWaiting(best) {
            stage = .already(best)
        } else {
            stage = .found(best)
        }
    }

    private func take(_ feed: DiscoveredFeed) {
        subscribe(feed)
        stage = .subscribed(feed.title)

        // Long enough to read, short enough not to be in the way.
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            done()
        }
    }
}
