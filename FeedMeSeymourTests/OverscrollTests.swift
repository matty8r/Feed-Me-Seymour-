//
//  OverscrollTests.swift
//  Feed Me, Seymour! Tests
//
//  Pull-past-the-end navigation. The hard part isn't the pull, it's refusing
//  the pulls that weren't asked for — a hard flick through a short article
//  reaches the bottom and shoots past it in one gesture, and turning the page
//  there would lose the reader's place.
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Pull to change article")
struct OverscrollTests {

    /// A 1000pt article in an 800pt window, so 200pt of travel.
    private func reading(_ offset: CGFloat,
                         contentHeight: CGFloat = 1000,
                         containerHeight: CGFloat = 800,
                         insetTop: CGFloat = 0,
                         insetBottom: CGFloat = 0) -> OverscrollReading {
        OverscrollReading.from(contentOffsetY: offset,
                               insetTop: insetTop,
                               insetBottom: insetBottom,
                               containerHeight: containerHeight,
                               contentHeight: contentHeight)
    }

    // MARK: - Reading the scroll view

    @Test("Resting at the top is neither pulled nor at the bottom")
    func atTop() {
        let r = reading(0)
        #expect(r.pull == 0)
        #expect(r.isAtTop)
        #expect(!r.isAtBottom)
    }

    @Test("Mid-article is against neither edge")
    func middle() {
        let r = reading(100)
        #expect(r.pull == 0)
        #expect(!r.isAtTop)
        #expect(!r.isAtBottom)
    }

    @Test("Past the bottom reads as a positive pull")
    func pastBottom() {
        let r = reading(260)
        #expect(r.pull == 60)
        #expect(r.isAtBottom)
    }

    @Test("Past the top reads as a negative pull")
    func pastTop() {
        let r = reading(-40)
        #expect(r.pull == -40)
        #expect(r.isAtTop)
    }

    @Test("Content insets count as part of the container")
    func insets() {
        // 1000pt of content, 800pt window, 60pt of chrome top and bottom: the
        // travel is 1000 - (800 - 120) = 320.
        let r = reading(-60 + 320, insetTop: 60, insetBottom: 60)
        #expect(r.pull == 0)
        #expect(r.isAtBottom)
    }

    @Test("An article shorter than the window is against both edges at once")
    func shortArticle() {
        let r = reading(0, contentHeight: 300, containerHeight: 800)
        #expect(r.isAtTop)
        #expect(r.isAtBottom)
        #expect(r.pull == 0)
    }

    // MARK: - Deciding

    @Test("Pulling past the bottom from a standstill turns the page")
    func pullFromBottom() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))       // already resting at the bottom
        t.moved(reading(300))               // 100pt past it
        #expect(t.endedDragging() == .bottom)
    }

    @Test("Pulling past the top goes back")
    func pullFromTop() {
        var t = OverscrollTracker()
        t.beganDragging(reading(0))
        t.moved(reading(-120))
        #expect(t.endedDragging() == .top)
    }

    @Test("A short pull does nothing")
    func shortPull() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))
        t.moved(reading(260))               // 60pt, under the 92pt threshold
        #expect(t.endedDragging() == nil)
    }

    /// The regression this whole design exists for.
    @Test("Scrolling to the end and overshooting in one drag does not turn the page")
    func flickThroughShortArticle() {
        var t = OverscrollTracker()
        t.beganDragging(reading(40))        // started mid-article, not at an edge
        t.moved(reading(200))               // arrived at the bottom
        t.moved(reading(400))               // and sailed 200pt past it
        #expect(t.endedDragging() == nil)
    }

    @Test("The page turns only on the second gesture")
    func secondGestureWins() {
        var t = OverscrollTracker()
        t.beganDragging(reading(40))
        t.moved(reading(400))
        #expect(t.endedDragging() == nil)

        t.beganDragging(reading(200))       // now resting at the bottom
        t.moved(reading(320))
        #expect(t.endedDragging() == .bottom)
    }

    @Test("Pulling the wrong way from an edge is ignored")
    func wrongDirection() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))       // armed at the bottom
        t.moved(reading(0))                 // scrolled back up to the top
        t.moved(reading(-150))              // and pulled past it
        #expect(t.endedDragging() == nil)
    }

    @Test("A short article can be pulled either way")
    func shortArticleEitherWay() {
        var forward = OverscrollTracker()
        forward.beganDragging(reading(0, contentHeight: 300))
        forward.moved(reading(120, contentHeight: 300))
        #expect(forward.endedDragging() == .bottom)

        var back = OverscrollTracker()
        back.beganDragging(reading(0, contentHeight: 300))
        back.moved(reading(-120, contentHeight: 300))
        #expect(back.endedDragging() == .top)
    }

    @Test("Letting go without ever dragging does nothing")
    func strayPhaseChange() {
        var t = OverscrollTracker()
        #expect(t.endedDragging() == nil)
    }

    @Test("The peak is what counts, not where the band happened to be at lift-off")
    func peakNotFinal() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))
        t.moved(reading(320))               // 120pt past — over the threshold
        t.moved(reading(210))               // already springing back on release
        #expect(t.endedDragging() == .bottom)
    }

    @Test("Each drag starts clean")
    func resetsBetweenDrags() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))
        t.moved(reading(400))
        #expect(t.endedDragging() == .bottom)

        t.beganDragging(reading(100))       // mid-article
        #expect(t.endedDragging() == nil)
    }

    // MARK: - What the indicator shows

    @Test("Progress fills towards the threshold and stops there")
    func progress() {
        var t = OverscrollTracker()
        t.beganDragging(reading(200))
        t.moved(reading(223))
        #expect(abs(t.progress - 0.25) < 0.001)
        t.moved(reading(400))
        #expect(t.progress == 1)
        #expect(t.isArmed)
    }

    @Test("No indicator until a pull is actually armed at an edge")
    func indicatorOnlyWhenArmed() {
        var t = OverscrollTracker()
        t.beganDragging(reading(40))        // mid-article
        t.moved(reading(400))
        #expect(t.activeEdge == nil)

        t.endedDragging()
        t.beganDragging(reading(200))
        t.moved(reading(240))
        #expect(t.activeEdge == .bottom)
    }
}
