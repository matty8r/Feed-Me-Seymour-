//
//  OverscrollNavigation.swift
//  Feed Me, Seymour!
//
//  Keep pulling at the end of an article and you fall into the next one; keep
//  pulling at the top and you back out to the one before. The gesture every
//  reader on the phone has trained people to expect, and the one that lets you
//  work down a morning's timeline without reaching for the chrome.
//
//  The decision is kept in `OverscrollTracker`, away from SwiftUI, because the
//  interesting part is not the drawing — it's knowing the difference between
//  someone scrolling hard to the end of a short article and someone asking for
//  the next one.
//

import SwiftUI

/// What the indicator promises. `nil` when there is nothing that way.
struct OverscrollDestination {
    let title: String
}

enum OverscrollEdge {
    case top, bottom
}

/// Where the scroll view is, reduced to the three things the gesture cares
/// about.
struct OverscrollReading: Equatable {
    /// Signed rubber-band distance: positive past the bottom, negative past the
    /// top, zero anywhere in between.
    var pull: CGFloat
    var isAtTop: Bool
    var isAtBottom: Bool

    /// Anything within a point of the edge counts as being at it; scroll views
    /// settle on fractional offsets.
    static func from(contentOffsetY: CGFloat,
                     insetTop: CGFloat,
                     insetBottom: CGFloat,
                     containerHeight: CGFloat,
                     contentHeight: CGFloat,
                     tolerance: CGFloat = 1) -> OverscrollReading {
        let y = contentOffsetY + insetTop
        let visible = containerHeight - insetTop - insetBottom
        let maxY = max(contentHeight - visible, 0)

        let pull: CGFloat
        if y < 0 { pull = y }
        else if y > maxY { pull = y - maxY }
        else { pull = 0 }

        return OverscrollReading(pull: pull,
                                 isAtTop: y <= tolerance,
                                 isAtBottom: y >= maxY - tolerance)
    }
}

/// Turns a drag into a decision.
///
/// The rule that makes this feel right rather than twitchy: the gesture only
/// arms if the article was *already* resting against that edge when the finger
/// went down. Otherwise one hard flick through a short article would both reach
/// the bottom and shoot past it, and you'd lose your place without asking.
struct OverscrollTracker {

    /// How far past the edge the pull has to go before letting go does anything.
    var threshold: CGFloat = 92

    private(set) var armedEdge: OverscrollEdge?
    /// The furthest the finger got this drag, read at lift-off — by then the
    /// band has already begun snapping back.
    private(set) var peak: CGFloat = 0
    private(set) var pull: CGFloat = 0

    var isDragging: Bool { isTracking }
    private var isTracking = false
    /// An article shorter than the window rests against both edges at once, so
    /// which way it goes can only be known once the finger moves.
    private var canArmEitherWay = false

    /// 0…1 towards the threshold, for the indicator.
    var progress: Double {
        guard threshold > 0 else { return 0 }
        return min(Double(abs(pull) / threshold), 1)
    }

    var isArmed: Bool { armedEdge != nil && abs(pull) >= threshold }

    /// The edge being pulled right now, or nil when the pull is going the wrong
    /// way for the edge we started from.
    var activeEdge: OverscrollEdge? {
        guard let armedEdge, pull != 0 else { return nil }
        switch armedEdge {
        case .bottom: return pull > 0 ? .bottom : nil
        case .top:    return pull < 0 ? .top : nil
        }
    }

    mutating func beganDragging(_ reading: OverscrollReading) {
        isTracking = true
        peak = 0
        pull = reading.pull
        // Resting against an edge is what earns the gesture. A short article
        // sits against both at once, and either direction is fair.
        canArmEitherWay = false
        if reading.isAtTop, reading.isAtBottom {
            armedEdge = nil
            canArmEitherWay = true
        } else if reading.isAtBottom, reading.pull >= 0 {
            armedEdge = .bottom
        } else if reading.isAtTop, reading.pull <= 0 {
            armedEdge = .top
        } else {
            armedEdge = nil
        }
    }

    mutating func moved(_ reading: OverscrollReading) {
        pull = reading.pull
        guard isTracking else { return }
        if armedEdge == nil, canArmEitherWay, reading.pull != 0 {
            armedEdge = reading.pull > 0 ? .bottom : .top
        }
        if abs(reading.pull) > abs(peak) { peak = reading.pull }
    }

    /// The edge to navigate to, if the drag earned it. Resets either way.
    mutating func endedDragging() -> OverscrollEdge? {
        defer {
            isTracking = false
            armedEdge = nil
            canArmEitherWay = false
            peak = 0
        }
        guard isTracking, let armedEdge, abs(peak) >= threshold else { return nil }
        switch armedEdge {
        case .bottom: return peak > 0 ? .bottom : nil
        case .top:    return peak < 0 ? .top : nil
        }
    }

    mutating func reset() {
        isTracking = false
        armedEdge = nil
        canArmEitherWay = false
        peak = 0
        pull = 0
    }
}

#if os(iOS)
import UIKit

private struct OverscrollNavigator: ViewModifier {

    let next: OverscrollDestination?
    let previous: OverscrollDestination?
    let goToNext: () -> Void
    let goToPrevious: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tracker = OverscrollTracker()
    @State private var hasBuzzed = false

    private func destination(for edge: OverscrollEdge?) -> OverscrollDestination? {
        switch edge {
        case .bottom: return next
        case .top:    return previous
        case nil:     return nil
        }
    }

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .onScrollGeometryChange(for: OverscrollReading.self) { geometry in
                OverscrollReading.from(
                    contentOffsetY: geometry.contentOffset.y,
                    insetTop: geometry.contentInsets.top,
                    insetBottom: geometry.contentInsets.bottom,
                    containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, reading in
                tracker.moved(reading)
                buzzIfNewlyArmed()
            }
            .onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting:
                    guard !tracker.isDragging else { return }
                    tracker.beganDragging(
                        OverscrollReading.from(
                            contentOffsetY: context.geometry.contentOffset.y,
                            insetTop: context.geometry.contentInsets.top,
                            insetBottom: context.geometry.contentInsets.bottom,
                            containerHeight: context.geometry.containerSize.height,
                            contentHeight: context.geometry.contentSize.height
                        )
                    )
                    hasBuzzed = false
                default:
                    switch tracker.endedDragging() {
                    case .bottom where next != nil:
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        goToNext()
                    case .top where previous != nil:
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        goToPrevious()
                    default:
                        break
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if tracker.activeEdge == .bottom, let next {
                    indicator(next, symbol: "arrow.down", caption: "Next", edge: .bottom)
                }
            }
            .overlay(alignment: .top) {
                if tracker.activeEdge == .top, let previous {
                    indicator(previous, symbol: "arrow.up", caption: "Previous", edge: .top)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tracker.isArmed)
            .onDisappear { tracker.reset() }
    }

    /// One tap the moment it becomes releasable, so the gesture can be finished
    /// without watching the screen.
    private func buzzIfNewlyArmed() {
        guard destination(for: tracker.activeEdge) != nil else { return }
        if tracker.isArmed, !hasBuzzed {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            hasBuzzed = true
        } else if !tracker.isArmed {
            hasBuzzed = false
        }
    }

    private func indicator(_ destination: OverscrollDestination,
                           symbol: String,
                           caption: String,
                           edge: VerticalEdge) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().stroke(palette.rule, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: tracker.progress)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tracker.isArmed ? palette.accent : palette.secondaryInk)
                    .rotationEffect(.degrees(tracker.isArmed && !reduceMotion ? 180 : 0))
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text(tracker.isArmed ? "Release" : caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tracker.isArmed ? palette.accent : palette.tertiaryInk)
                    .textCase(.uppercase)
                Text(destination.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.rule.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 12, y: edge == .bottom ? 5 : -5)
        .padding(edge == .bottom ? .bottom : .top, 18)
        // Ride out with the finger rather than sitting pinned to the edge.
        .offset(y: (edge == .bottom ? -1 : 1) * min(abs(tracker.pull), tracker.threshold * 1.3) * 0.45)
        .frame(maxWidth: 320)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}
#endif

extension View {
    /// Pull-past-the-end navigation. Touch only: on the Mac the same moves are
    /// `J` / `K` and the toolbar chevrons, and a trackpad's inertia would fire
    /// this by accident.
    func overscrollArticleNavigation(
        next: OverscrollDestination?,
        previous: OverscrollDestination?,
        goToNext: @escaping () -> Void,
        goToPrevious: @escaping () -> Void
    ) -> some View {
        #if os(iOS)
        modifier(OverscrollNavigator(next: next,
                                     previous: previous,
                                     goToNext: goToNext,
                                     goToPrevious: goToPrevious))
        #else
        self
        #endif
    }
}
