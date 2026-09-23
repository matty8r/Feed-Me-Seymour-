//
//  CloudKitActivity.swift
//  Feed Me, Seymour!
//
//  What CloudKit actually did, as opposed to what the app tried to do.
//
//  This exists because the two are not the same, and the difference is
//  invisible at exactly the moment it matters. The reconcile pass can run
//  perfectly — reading the mirror store, writing its own records — while every
//  one of those records is being rejected by the server. Reporting "last
//  synced" from the end of that pass is reporting that the app asked, not that
//  anything arrived.
//
//  `NSPersistentCloudKitContainer` publishes setup, import and export events
//  with their errors. That is the truth, so it is what the app says.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class CloudKitActivity {

    enum Phase: String {
        case setup, importing = "import", exporting = "export"

        init?(_ type: NSPersistentCloudKitContainer.EventType) {
            switch type {
            case .setup: self = .setup
            case .import: self = .importing
            case .export: self = .exporting
            @unknown default: return nil
            }
        }

        var describedInThePast: String {
            switch self {
            case .setup: "Setting up"
            case .importing: "Download"
            case .exporting: "Upload"
            }
        }
    }

    struct Outcome {
        var phase: Phase
        var endedAt: Date
        var error: Error?
        var succeeded: Bool { error == nil }
    }

    private(set) var lastSuccess: Outcome?
    private(set) var lastFailure: Outcome?

    /// Setup failing is not one bad pass. The mirroring delegate gives up for
    /// the lifetime of the process and refuses everything afterwards with
    /// "never successfully initialized" — so nothing will work again, however
    /// many times you refresh, until the app is relaunched. Worth saying out
    /// loud rather than leaving someone to discover it.
    private(set) var needsRelaunch = false

    // nonisolated so deinit can let it go; only ever written in init.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        observer = notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.record(event) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        // Events arrive twice: once when they start, once when they end.
        guard let endedAt = event.endDate, let phase = Phase(event.type) else { return }

        let outcome = Outcome(phase: phase, endedAt: endedAt, error: event.error)
        if outcome.succeeded {
            lastSuccess = outcome
            if phase == .setup { needsRelaunch = false }
        } else {
            lastFailure = outcome
            if phase == .setup { needsRelaunch = true }
        }
    }

    /// One line for the Settings screen. A failure outranks a success, because
    /// a device that uploaded fine an hour ago and has been failing since is
    /// not syncing, and shouldn't claim to be.
    var summary: String? {
        if needsRelaunch {
            return "iCloud stopped after an error. Quit and reopen Feed Me, Seymour! to start it again."
        }
        if let lastFailure, lastFailure.endedAt > (lastSuccess?.endedAt ?? .distantPast) {
            return "\(lastFailure.phase.describedInThePast) failed \(lastFailure.endedAt.relativeStamp): \(Self.describe(lastFailure.error))"
        }
        if let lastSuccess {
            return "\(lastSuccess.phase.describedInThePast) finished \(lastSuccess.endedAt.relativeStamp)."
        }
        return nil
    }

    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "unknown error" }
        // The partial-failure case is the one worth naming: it means the
        // server rejected particular records, which usually means the schema
        // in this environment doesn't have a field the app is writing.
        if error.domain == "CKErrorDomain", error.code == 2 {
            return "iCloud rejected some records (partial failure)."
        }
        return error.localizedDescription
    }
}
