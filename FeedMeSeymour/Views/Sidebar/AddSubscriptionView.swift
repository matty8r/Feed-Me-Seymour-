//
//  AddSubscriptionView.swift
//  Feed Me, Seymour!
//
//  Paste anything — a site, a feed, a `feed://` link — and the app goes and
//  finds the actual feed before it commits the reader to anything.
//

import SwiftUI
import SwiftData

struct AddSubscriptionView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var results: [DiscoveredFeed] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    @Query private var existingFeeds: [Feed]

    private var existingURLs: Set<URL> { Set(existingFeeds.map(\.feedURL)) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                field
                Divider()
                content
            }
            .background(palette.canvas)
            .navigationTitle("Add Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 470)
        #endif
        .onAppear { isFieldFocused = true }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Input

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(palette.tertiaryInk)

            TextField("theverge.com, or a feed URL", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFieldFocused)
                .onSubmit(search)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                #endif

            if !input.isEmpty {
                Button {
                    input = ""
                    results = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryInk)
                }
                .buttonStyle(.plain)
            }

            Button(action: search) {
                if isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Find")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmed.isEmpty || isSearching)
        }
        .padding(16)
    }

    // MARK: - Results

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("No Feed Found", systemImage: "questionmark.circle")
            } description: {
                Text(errorMessage)
            }
        } else if results.isEmpty && !isSearching {
            suggestions
        } else {
            List {
                ForEach(results) { result in
                    resultRow(result)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func resultRow(_ result: DiscoveredFeed) -> some View {
        let alreadySubscribed = existingURLs.contains(result.url)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text(result.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button(alreadySubscribed ? "Added" : "Subscribe") {
                    subscribe(result)
                }
                .buttonStyle(.borderedProminent)
                .disabled(alreadySubscribed)
            }

            if let subtitle = result.subtitle?.nilIfEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(2)
            }

            if !result.sampleHeadlines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(result.sampleHeadlines.prefix(3), id: \.self) { headline in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(palette.tertiaryInk)
                                .frame(width: 3, height: 3)
                            Text(headline)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Try one of these")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(palette.tertiaryInk)

                ForEach(Persistence.starterFeeds) { entry in
                    Button {
                        input = entry.url
                        search()
                    } label: {
                        HStack {
                            Text(entry.title)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Hairline()
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func search() {
        let query = input.trimmed
        guard !query.isEmpty else { return }

        searchTask?.cancel()
        errorMessage = nil
        results = []
        isSearching = true

        searchTask = Task { @MainActor in
            let found = await FeedDiscovery.discover(from: query)
            guard !Task.isCancelled else { return }
            isSearching = false
            if found.isEmpty {
                errorMessage = "Nothing at “\(query)” looked like an RSS, Atom or JSON feed."
            } else {
                results = found
                // One unambiguous answer: don't make the reader click twice.
                if found.count == 1, !existingURLs.contains(found[0].url) {
                    subscribe(found[0])
                }
            }
        }
    }

    private func subscribe(_ discovered: DiscoveredFeed) {
        let feed = model.refresher.subscribe(to: discovered, in: context)
        model.showStatus("Subscribed to \(feed.displayTitle).")
        Task { @MainActor in
            await model.refresher.refresh(feed, in: context)
            model.select(.feed(feed.persistentModelID))
        }
        dismiss()
    }
}
