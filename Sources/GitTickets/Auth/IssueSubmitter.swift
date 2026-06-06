import Foundation

/// Abstract submission entry point. ``RelaySubmitter`` is the only
/// production conformer today; a Device Flow submitter is on the roadmap.
/// The UI layer dispatches against this protocol so it never branches on
/// ``AuthMode``.
///
/// Phase 2 surface — ``fetchMyIssues(submissionIDs:deviceID:)`` and
/// ``fetchReplies(submissionID:deviceID:)`` — have default implementations
/// that throw `.payloadInvalid("This submitter does not support ...")` so
/// submitters can opt in incrementally. ``RelaySubmitter`` overrides both
/// against the relay's `/my-issues` endpoint.
protocol IssueSubmitter: Sendable {
    /// Submits the report and returns the created issue.
    func submit(_ report: Report) async throws -> SubmittedIssue

    /// Fetches recent submissions for this device. Used by the Phase 2
    /// "My Issues" view.
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue]

    /// Returns the current reply count + latest reply timestamp for one
    /// issue. Used by the Phase 2 reply-polling path.
    func fetchReplies(submissionID: UUID, deviceID: String) async throws -> (replyCount: Int, latestReplyAt: Date?)
}

extension IssueSubmitter {
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue] {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support My Issues lookup.")
    }

    func fetchReplies(submissionID: UUID, deviceID: String) async throws -> (replyCount: Int, latestReplyAt: Date?) {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support reply polling.")
    }
}
