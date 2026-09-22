//
//  NavigationTests.swift
//  Feed Me, Seymour! Tests
//
//  The current article: the one the timeline has highlighted and the one the
//  reader is showing, which are deliberately the same thing so the keyboard can
//  move it from either side.
//

import Testing
import Foundation
import SwiftData
@testable import FeedMeSeymour

@MainActor
@Suite("Current article")
struct NavigationTests {

    private func makeModel(articleCount: Int = 3) -> (AppModel, [PersistentIdentifier], ModelContext) {
        let context = ModelContext(Persistence.makeInMemoryContainer())
        var ids: [PersistentIdentifier] = []
        for i in 0..<articleCount {
            let article = Article(guid: "a\(i)", title: "Article \(i)", publishedAt: .now)
            context.insert(article)
            ids.append(article.persistentModelID)
        }
        let model = AppModel(isCloudBacked: false)
        model.visibleArticleIDs = ids
        return (model, ids, context)
    }

    // MARK: - Changing what you're looking at

    @Test("Changing feed closes the reader")
    func changingFeedClosesReader() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[1]
        model.expandedArticleID = ids[1]
        #expect(model.isReaderExpanded)

        model.selection = .unread

        #expect(!model.isReaderExpanded)
        #expect(model.selectedArticleID == nil)
    }

    /// The sidebar binds a List straight at `selection`, so the rule can't live
    /// in a helper the List never calls.
    @Test("Assigning selection directly closes the reader too")
    func directAssignmentClosesReader() {
        let (model, ids, _) = makeModel()
        model.expandedArticleID = ids[0]
        model.selection = .feed(ids[0])
        #expect(!model.isReaderExpanded)
    }

    @Test("Re-picking the feed you're already on leaves the reader alone")
    func samefeedKeepsReader() {
        let (model, ids, _) = makeModel()
        model.selection = .unread
        model.selectedArticleID = ids[2]
        model.expandedArticleID = ids[2]

        model.selection = .unread

        #expect(model.isReaderExpanded)
        #expect(model.selectedArticleID == ids[2])
    }

    // MARK: - Moving

    @Test("Down and up move the current article")
    func moveThroughTimeline() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[0]

        model.goToNext()
        #expect(model.selectedArticleID == ids[1])
        model.goToNext()
        #expect(model.selectedArticleID == ids[2])
        model.goToPrevious()
        #expect(model.selectedArticleID == ids[1])
    }

    @Test("Moving inside the reader keeps the reader open")
    func moveInsideReader() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[0]
        model.expandedArticleID = ids[0]

        model.goToNext()

        #expect(model.isReaderExpanded)
        #expect(model.expandedArticleID == ids[1])
        #expect(model.selectedArticleID == ids[1])
    }

    @Test("Moving in the timeline does not open the reader")
    func moveOutsideReaderStaysClosed() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[0]
        model.goToNext()
        #expect(!model.isReaderExpanded)
        #expect(model.selectedArticleID == ids[1])
    }

    @Test("The ends of the list hold")
    func stopsAtTheEnds() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[0]
        #expect(!model.canGoToPrevious)
        model.goToPrevious()
        #expect(model.selectedArticleID == ids[0])

        model.selectedArticleID = ids[2]
        #expect(!model.canGoToNext)
        model.goToNext()
        #expect(model.selectedArticleID == ids[2])
    }

    @Test("With nothing current yet, moving down starts at the top")
    func startsAtTheTop() {
        let (model, ids, _) = makeModel()
        #expect(model.selectedArticleID == nil)
        model.goToNext()
        #expect(model.selectedArticleID == ids[0])
    }

    @Test("What's next is what the indicator promises")
    func neighbours() {
        let (model, ids, _) = makeModel()
        model.selectedArticleID = ids[1]
        #expect(model.nextArticleID == ids[2])
        #expect(model.previousArticleID == ids[0])

        model.selectedArticleID = ids[2]
        #expect(model.nextArticleID == nil)
        #expect(model.previousArticleID == ids[1])
    }

    @Test("An empty timeline has nowhere to go")
    func emptyTimeline() {
        let model = AppModel(isCloudBacked: false)
        model.visibleArticleIDs = []
        #expect(!model.canGoToNext)
        #expect(!model.canGoToPrevious)
        #expect(model.goToNext() == nil)
        #expect(model.nextArticleID == nil)
    }
}
