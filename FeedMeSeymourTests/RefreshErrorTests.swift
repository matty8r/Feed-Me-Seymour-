//
//  RefreshErrorTests.swift
//  Feed Me, Seymour! Tests
//
//  What counts as a subscription failing, and what is only the app changing
//  its mind.
//

import Testing
import Foundation
@testable import FeedMeSeymour

@Suite("Refresh failures")
struct RefreshErrorTests {

    /// URLSession reports an interrupted request this way, and its
    /// `localizedDescription` is the bare word "cancelled" — which is what
    /// used to appear in the status banner at launch, attributed to a feed
    /// that was perfectly fine.
    @Test("A cancelled URL request is not a failure")
    func urlCancellation() {
        let error = URLError(.cancelled)
        #expect(error.isCancellation)
    }

    @Test("A cancelled task is not a failure")
    func taskCancellation() {
        #expect(CancellationError().isCancellation)
    }

    @Test("Real network trouble still counts")
    func realFailures() {
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!URLError(.notConnectedToInternet).isCancellation)
        #expect(!URLError(.badServerResponse).isCancellation)
        #expect(!URLError(.cannotFindHost).isCancellation)
    }

    /// The same code on another domain means something else entirely, so the
    /// domain has to be part of the test.
    @Test("A matching code in another domain is not cancellation")
    func otherDomain() {
        let imposter = NSError(domain: "com.example.something", code: NSURLErrorCancelled)
        #expect(!imposter.isCancellation)
    }
}
