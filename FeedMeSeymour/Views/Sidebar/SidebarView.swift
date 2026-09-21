//
//  SidebarView.swift
//  Feed Me, Seymour!
//
//  Two tabs — Feeds and Favorites — and one unmistakable button in the bottom
//  right for adding a subscription.
//

import SwiftUI
import SwiftData

struct SidebarView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Picker("View", selection: $model.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            Group {
                switch model.sidebarTab {
                case .subscriptions:
                    SubscriptionListView()
                case .favorites:
                    FavoritesListView()
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: model.sidebarTab)
        .overlay(alignment: .bottomTrailing) { addButton }
        .navigationTitle("Feed Me, Seymour!")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { sidebarToolbar }
    }

    // MARK: - The button

    @ViewBuilder
    private var addButton: some View {
        if model.sidebarTab == .subscriptions {
            Button {
                model.isShowingAddSubscription = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(palette.accent.gradient)
                            .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
                    }
            }
            .buttonStyle(AddButtonStyle())
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .help("Add Subscription")
            .accessibilityLabel("Add Subscription")
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await model.refresher.refreshAll(in: context) }
            } label: {
                if model.refresher.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(model.refresher.isRefreshing)
            .help("Refresh All Subscriptions")
        }

        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                model.isShowingSettings = true
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Reading Settings")
        }
        #endif
    }
}

private struct AddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
