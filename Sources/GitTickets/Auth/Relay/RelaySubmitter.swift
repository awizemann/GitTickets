import Foundation

/// The default submitter — talks to a developer-hosted relay.
///
/// Orchestrates the full submission pipeline:
///
/// 1. Upload the screenshot (if any) via `POST /attachment`.
/// 2. Upload each additional attachment via `POST /attachment`.
/// 3. Assemble the markdown body via ``IssueBodyBuilder`` — including the
///    pre-redacted ``Report/diagnosticsBlob`` if present (the form pre-collected
///    it; the submitter never re-collects).
/// 4. `POST /report` with the assembled body, labels, submission ID,
///    device ID, and user-agent.
/// 5. Upsert the result into ``SubmissionCache`` so the Phase 2 "My Issues"
///    view can list it offline.
/// 6. Return the ``SubmittedIssue``.
///
/// Concurrency: `Sendable` and stateless beyond the injected dependencies.
struct RelaySubmitter: IssueSubmitter {

    let configuration: Configuration
    let client: RelayClient
    let cache: SubmissionCache?
    let userAgent: String
    let clock: @Sendable () -> Date

    init?(
        configuration: Configuration,
        cache: SubmissionCache? = nil,
        userAgent: String = UserAgent.string(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        guard case let .relay(url, secret) = configuration.auth else { return nil }
        self.configuration = configuration
        self.client = RelayClient(baseURL: url, secret: secret, clock: clock)
        self.cache = cache
        self.userAgent = userAgent
        self.clock = clock
    }

    /// Override for tests that want to inject a pre-built ``RelayClient``.
    init(
        configuration: Configuration,
        client: RelayClient,
        cache: SubmissionCache? = nil,
        userAgent: String = UserAgent.string(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.client = client
        self.cache = cache
        self.userAgent = userAgent
        self.clock = clock
    }

    func submit(_ report: Report) async throws -> SubmittedIssue {
        try Self.validate(report)

        // 1. Upload screenshot if present.
        var screenshotURL: URL?
        if let screenshot = report.screenshot {
            let attachment = ReportAttachment(filename: "screenshot.png", mimeType: "image/png", data: screenshot)
            let response = try await client.uploadAttachment(attachment)
            screenshotURL = URL(string: response.url)
        }

        // 2. Upload other attachments.
        var uploaded: [UploadedAttachment] = []
        for attachment in report.attachments {
            let response = try await client.uploadAttachment(attachment)
            guard let url = URL(string: response.url) else {
                throw GitTicketsError.payloadInvalid(reason: "Relay returned malformed attachment URL")
            }
            uploaded.append(UploadedAttachment(
                filename: attachment.filename,
                url: url,
                mimeType: attachment.mimeType
            ))
        }

        // 3. Assemble the body.
        let body = IssueBodyBuilder.build(
            report: report,
            diagnostics: report.includeDiagnostics ? report.diagnosticsBlob : nil,
            screenshotURL: screenshotURL,
            attachments: uploaded
        )

        // 4. POST /report.
        let labels = BodyTemplates.defaultLabels(for: report.kind) + [configuration.myIssues.label]
        let request = RelayReportRequest(
            title: report.title,
            body: body,
            kind: report.kind.rawValue,
            labels: labels,
            submissionID: report.submissionID.uuidString,
            deviceID: report.deviceID,
            attachmentURLs: uploaded.map(\.url.absoluteString),
            userAgent: userAgent
        )
        let response = try await client.postReport(request)

        guard let issueURL = URL(string: response.issueURL) else {
            throw GitTicketsError.payloadInvalid(reason: "Relay returned malformed issue URL")
        }

        let createdAt = Self.parseISO8601(response.createdAt) ?? clock()
        let submitted = SubmittedIssue(
            id: report.submissionID,
            issueNumber: response.issueNumber,
            issueURL: issueURL,
            title: response.title,
            createdAt: createdAt
        )

        // 5. Upsert into cache (best-effort — cache failures don't fail submission).
        if let cache {
            let record = SubmissionRecord(
                submissionID: report.submissionID,
                issueNumber: response.issueNumber,
                issueURL: issueURL,
                title: response.title,
                kind: report.kind,
                body: body,
                deviceID: report.deviceID,
                createdAt: createdAt,
                submittedAt: clock()
            )
            try? cache.upsert(record)
        }

        return submitted
    }

    // MARK: - Helpers

    private static func validate(_ report: Report) throws {
        let trimmedTitle = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            throw GitTicketsError.payloadInvalid(reason: "Title is required")
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseISO8601(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFractional.date(from: string)
    }
}
