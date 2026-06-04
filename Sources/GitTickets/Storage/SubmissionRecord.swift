import Foundation

/// A SQLite row representing one submitted issue, plus local-only fields
/// (cached body, submission timestamp, read state) that aren't part of the
/// public ``SubmittedIssue`` projection.
struct SubmissionRecord: Sendable, Hashable {

    /// Matches ``Report/submissionID``. Primary key in SQLite.
    let submissionID: UUID

    /// GitHub issue number.
    let issueNumber: Int

    /// HTTPS URL on github.com.
    let issueURL: URL

    /// Issue title at submit time.
    let title: String

    /// Report kind (`bug`, `featureRequest`, `question`).
    let kind: ReportKind

    /// Final markdown body posted to GitHub. Cached for offline detail-view.
    let body: String

    /// The stable device identifier at submit time.
    let deviceID: String

    /// When the GitHub issue was created (returned by the API).
    let createdAt: Date

    /// When the SDK submitted the report (may slightly precede `createdAt`).
    let submittedAt: Date

    /// Most recent comment timestamp, if any.
    var latestReplyAt: Date?

    /// Total comments seen for this issue.
    var replyCount: Int

    /// Comments the user has acknowledged in-app.
    var readReplyCount: Int

    /// Number of replies the user hasn't read yet.
    var unreadReplyCount: Int { max(0, replyCount - readReplyCount) }

    init(
        submissionID: UUID,
        issueNumber: Int,
        issueURL: URL,
        title: String,
        kind: ReportKind,
        body: String,
        deviceID: String,
        createdAt: Date,
        submittedAt: Date,
        latestReplyAt: Date? = nil,
        replyCount: Int = 0,
        readReplyCount: Int = 0
    ) {
        self.submissionID = submissionID
        self.issueNumber = issueNumber
        self.issueURL = issueURL
        self.title = title
        self.kind = kind
        self.body = body
        self.deviceID = deviceID
        self.createdAt = createdAt
        self.submittedAt = submittedAt
        self.latestReplyAt = latestReplyAt
        self.replyCount = replyCount
        self.readReplyCount = readReplyCount
    }

    /// Projects to the public ``SubmittedIssue`` shape surfaced via the API.
    var asSubmittedIssue: SubmittedIssue {
        SubmittedIssue(
            id: submissionID,
            issueNumber: issueNumber,
            issueURL: issueURL,
            title: title,
            createdAt: createdAt,
            latestReplyAt: latestReplyAt,
            replyCount: replyCount,
            unreadReplyCount: unreadReplyCount
        )
    }
}
