//
//  MyIssuesRefresh.swift
//  GitTickets — the result of refreshing "My Reports", including what the
//  backend did NOT return.
//
//  Why this exists: "My Reports" is narrowed twice. The relay lists issues
//  carrying the configured label, then matches embedded submission-ID markers
//  against the IDs the client asked about. An issue whose label was never
//  applied — or was removed later — fails the FIRST narrowing, so it can never
//  match the second. The backend answers 200 with zero matches. That is
//  indistinguishable, from `[SubmittedIssue]` alone, from "this user has never
//  filed anything", so the screen went quietly empty and stayed that way.
//
//  ``SubmittedIssue/missingLabels`` already catches the label being dropped at
//  SUBMIT time. It cannot catch a label removed from existing issues in bulk, a
//  changed label on the relay, or a swapped repo — in all three the user files
//  nothing new, so nothing fires, yet every past report disappears. Comparing
//  what was asked for against what came back catches all of them.
//

import Foundation

/// The outcome of a "My Reports" refresh: the issues the backend matched, and
/// how many locally cached submissions it was asked about.
///
/// Use ``allMissing`` to tell "you have no reports" apart from "we could not
/// find your reports" — they need very different words in front of a user.
public struct MyIssuesRefresh: Sendable, Equatable {

    /// The submissions the backend matched and returned.
    public let issues: [SubmittedIssue]

    /// How many locally cached submissions were looked up. Zero means this
    /// device has never filed anything, which is not a problem.
    public let requestedCount: Int

    public init(issues: [SubmittedIssue], requestedCount: Int) {
        self.issues = issues
        self.requestedCount = requestedCount
    }

    /// Cached submissions the backend did not return.
    ///
    /// A small number is ordinary — an issue can be deleted. A count equal to
    /// ``requestedCount`` is the signal worth acting on; see ``allMissing``.
    public var unmatchedCount: Int {
        max(0, requestedCount - issues.count)
    }

    /// `true` when this device has cached submissions but the backend matched
    /// **none** of them.
    ///
    /// - Important: this does **not** tell you why, and you must not present it
    ///   as though it did. The backend finds issues by label, so an issue is
    ///   absent from the result whether it was **deleted** or merely **lost its
    ///   label**. Both produce `allMissing == true` and they are
    ///   indistinguishable from here — distinguishing them would need a
    ///   per-issue existence probe the backend does not expose.
    ///
    ///   Causes, roughly in the order worth checking:
    ///   - every issue was deleted (ordinary, permanent, and nobody's fault)
    ///   - the label was never applied — the GitHub App lacks push permission
    ///   - the label was removed from the issues after the fact
    ///   - the backend's configured label or repository changed
    ///
    ///   Closed issues are **not** a cause: the backend lists with `state=all`.
    ///
    /// - Important: `requestedCount == 0` is NOT this case. A device that has
    ///   filed nothing legitimately has nothing to show.
    public var allMissing: Bool {
        requestedCount > 0 && issues.isEmpty
    }
}
