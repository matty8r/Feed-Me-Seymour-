//
//  StarButton.swift
//  Feed Me, Seymour!
//
//  The favourite control. It appears on every row and in the reader, and it is
//  the same button in both places so it always feels like the same gesture.
//

import SwiftUI

struct StarButton: View {

    let isStarred: Bool
    var size: Double = 15
    var showsLabel = false
    /// What the star looks like when it isn't lit. Faint on a timeline row,
    /// but full strength in a bar, where it sits among its peers.
    var idleTint: KeyPath<Palette, Color> = \.tertiaryInk
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var isPopping = false

    private var title: String {
        isStarred ? "Remove Bookmark" : "Add Bookmark"
    }

    var body: some View {
        Button(action: tapped) {
            HStack(spacing: 6) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(isStarred ? palette.favorite : palette[keyPath: idleTint])
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isPopping ? 1.3 : 1)
                if showsLabel {
                    Text(isStarred ? "Bookmarked" : "Bookmark")
                        .font(.callout)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isStarred ? [.isSelected] : [])
    }

    private func tapped() {
        action()
        guard !isStarred else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { isPopping = true }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.easeOut(duration: 0.22)) { isPopping = false }
        }
    }
}
