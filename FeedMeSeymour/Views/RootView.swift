//
//  RootView.swift
//  Feed Me, Seymour!
//
//  Two panes: subscriptions and favorites on the left, the chronological
//  timeline — and the reader that grows out of it — on the right.
//

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct RootView: View {

    @Environment(AppModel.self) private var model
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var exportDocument: OPMLDocument?

    private var palette: Palette {
        Palette(theme: settings.theme, colorScheme: colorScheme)
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 248, ideal: 292, max: 380)
        } detail: {
            TimelinePane()
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.palette, palette)
        .tint(palette.accent)
        .preferredColorScheme(settings.theme.forcedColorScheme)
        .background(palette.canvas)
        .overlay(alignment: .bottom) { statusBanner }
        .sheet(isPresented: $model.isShowingAddSubscription) {
            AddSubscriptionView()
                .environment(model)
                .environment(settings)
                .environment(\.palette, palette)
        }
        .fileImporter(
            isPresented: $model.isShowingOPMLImporter,
            allowedContentTypes: [.opml, .xml],
            allowsMultipleSelection: false
        ) { result in
            importOPML(result)
        }
        .fileExporter(
            isPresented: $model.isShowingOPMLExporter,
            document: exportDocument,
            contentType: .opml,
            defaultFilename: "Feed Me Seymour Subscriptions"
        ) { _ in }
        .onChange(of: model.isShowingOPMLExporter) { _, isShowing in
            // Only touch the store when the panel is actually about to appear.
            if isShowing { exportDocument = OPMLDocument(entries: exportEntries()) }
        }
        .task { await firstRun() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAll)) { _ in
            Task { await model.refresher.refreshAll(in: context) }
        }
        .onChange(of: model.refresher.lastErrorMessage) { _, message in
            if let message { model.showStatus(message) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshIfStale() }
        }
        .modifier(SettingsSheetModifier())
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanner: some View {
        if let message = model.statusMessage {
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.36, dampingFraction: 0.85), value: model.statusMessage)
        }
    }

    // MARK: - Lifecycle

    private func firstRun() async {
        Persistence.seedIfEmpty(context)
        await refreshIfStale()
    }

    private func refreshIfStale() async {
        let interval = TimeInterval(max(settings.refreshMinutes, 5) * 60)
        if let last = model.refresher.lastRefreshDate, Date.now.timeIntervalSince(last) < interval { return }
        await model.refresher.refreshAll(in: context)
    }

    // MARK: - OPML

    private func exportEntries() -> [OPMLEntry] {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        return feeds.map { OPMLEntry(title: $0.displayTitle, feedURL: $0.feedURL, homePageURL: $0.homePageURL) }
    }

    private func importOPML(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            model.showStatus("Couldn’t read that file.")
            return
        }

        let entries = OPML.entries(fromOPML: data)
        guard !entries.isEmpty else {
            model.showStatus("No subscriptions found in that file.")
            return
        }

        let existing = Set(((try? context.fetch(FetchDescriptor<Feed>())) ?? []).map(\.feedURL))
        var added = 0
        var index = existing.count
        for entry in entries where !existing.contains(entry.feedURL) {
            context.insert(
                Feed(feedURL: entry.feedURL, title: entry.title, homePageURL: entry.homePageURL, sortIndex: index)
            )
            index += 1
            added += 1
        }
        try? context.save()
        model.showStatus(added == 0 ? "Those subscriptions were already here." : "Added \(added) subscription\(added == 1 ? "" : "s").")
        Task { await model.refresher.refreshAll(in: context) }
    }
}

/// Settings live in the menu bar on macOS and in a sheet on iOS.
private struct SettingsSheetModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(ReaderSettings.self) private var settings

    func body(content: Content) -> some View {
        #if os(iOS)
        @Bindable var model = model
        return content.sheet(isPresented: $model.isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(model)
                    .environment(settings)
            }
        }
        #else
        return content
        #endif
    }
}

// MARK: - OPML document

extension UTType {
    static let opml = UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
}

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.opml, .xml] }
    static var writableContentTypes: [UTType] { [.opml, .xml] }

    var entries: [OPMLEntry]

    init(entries: [OPMLEntry]) { self.entries = entries }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries = OPML.entries(fromOPML: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(OPML.document(for: entries).utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
