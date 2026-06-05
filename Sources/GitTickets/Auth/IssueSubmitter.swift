import Foundation

/// Abstract submission entry point. Both ``RelaySubmitter`` (PR 8) and
/// `DeviceFlowSubmitter` (PR 11) conform to it. The UI layer (PR 12+)
/// dispatches against this protocol so it never branches on ``AuthMode``.
///
/// Phase 2 surface — `fetchMyIssues` and `fetchReplies` — has default
/// implementations that throw a not-supported error so submitters can opt
/// in incrementally (RelaySubmitter overrides them; an early Device Flow
/// submitter can ship without).
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
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support My Issues lookup yet.")
    }

    func fetchReplies(submissionID: UUID, deviceID: String) async throws -> (replyCount: Int, latestReplyAt: Date?) {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support reply polling yet.")
    }
}
