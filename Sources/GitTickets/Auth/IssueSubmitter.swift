import Foundation

/// Abstract submission entry point. Both ``RelaySubmitter`` (PR 8) and
/// `DeviceFlowSubmitter` (PR 11) conform to it. The UI layer (PR 12+)
/// dispatches against this protocol so it never branches on ``AuthMode``.
protocol IssueSubmitter: Sendable {
    func submit(_ report: Report) async throws -> SubmittedIssue
}
