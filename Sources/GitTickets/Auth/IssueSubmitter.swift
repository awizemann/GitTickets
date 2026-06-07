import Foundation

/// Abstract submission entry point. Both ``RelaySubmitter`` and
/// ``DeviceFlowSubmitter`` conform. The UI layer dispatches against this
/// protocol so it never branches on ``AuthMode``.
///
/// Phase 2 fetch surface — ``fetchMyIssues(submissionIDs:deviceID:)``,
/// ``fetchReplies(submissionID:deviceID:)``, and
/// ``fetchComments(issueNumber:deviceID:)`` — have default implementations
/// that throw `.payloadInvalid("This submitter does not support ...")` so
/// submitters can opt in incrementally.
protocol IssueSubmitter: Sendable {
    /// Submits the report and returns the created issue.
    func submit(_ report: Report) async throws -> SubmittedIssue

    /// Fetches recent submissions for this device. Used by the Phase 2
    /// "My Issues" view.
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue]

    /// Returns the current reply count + latest reply timestamp for one
    /// issue. Used by the Phase 2 reply-polling path.
    func fetchReplies(submissionID: UUID, deviceID: String) async throws -> (replyCount: Int, latestReplyAt: Date?)

    /// Fetches the comments on one GitHub issue, ordered oldest first.
    /// Used by ``IssueDetailView`` to render the in-app reply thread.
    func fetchComments(issueNumber: Int, deviceID: String) async throws -> [IssueComment]
}

extension IssueSubmitter {
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue] {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support My Issues lookup.")
    }

    func fetchReplies(submissionID: UUID, deviceID: String) async throws -> (replyCount: Int, latestReplyAt: Date?) {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support reply polling.")
    }

    func fetchComments(issueNumber: Int, deviceID: String) async throws -> [IssueComment] {
        throw GitTicketsError.payloadInvalid(reason: "This submitter does not support comment fetching.")
    }
}
