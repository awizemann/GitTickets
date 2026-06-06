import Foundation

/// The default submitter — talks to a developer-hosted relay.
///
/// Orchestrates the full submission pipeline:
///
/// 1. Check the local ``SubmissionCache`` for an existing record matching
///    the report's `submissionID` — if present, return that instead of
///    re-submitting (idempotency / retry safety).
/// 2. Upload screenshot + attachments concurrently via `POST /attachment`.
/// 3. Assemble the markdown body via ``IssueBodyBuilder`` — including the
///    pre-redacted ``Report/diagnosticsBlob`` if present (the form pre-collected
///    it; the submitter never re-collects).
/// 4. `POST /report` with the assembled body, labels, submission ID, and
///    device ID. The relay reads the User-Agent from the HTTP header.
/// 5. Compare the relay-reported `appliedLabels` against what we asked for
///    and surface any drops via ``SubmittedIssue/missingLabels``.
/// 6. Upsert the result into ``SubmissionCache`` so the Phase 2 "My Issues"
///    view can list it offline.
/// 7. Return the ``SubmittedIssue``.
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
        let http = HTTPClient(userAgent: userAgent)
        self.client = RelayClient(baseURL: url, secret: secret, http: http, clock: clock)
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

        // 1. Dedupe — if a prior submit completed for this submissionID,
        //    return the cached result. Protects against UI double-tap and
        //    transport-error retries the SDK was unable to retry safely.
        if let cache,
           let existing = try? cache.record(submissionID: report.submissionID) {
            return existing.asSubmittedIssue
        }

        // 2. Upload screenshot + all attachments concurrently. Each upload
        //    is independent — there's no reason to serialize a screenshot
        //    behind three log files when the relay can take them all.
        let uploadResult = try await uploadAll(report: report)
        let screenshotURL = uploadResult.screenshotURL
        let uploaded = uploadResult.attachments

        // 3. Assemble the body.
        let body = IssueBodyBuilder.build(
            report: report,
            diagnostics: report.includeDiagnostics ? report.diagnosticsBlob : nil,
            screenshotURL: screenshotURL,
            attachments: uploaded
        )

        // 4. POST /report.
        let requestedLabels = BodyTemplates.defaultLabels(for: report.kind) + [configuration.myIssues.label]
        let request = RelayReportRequest(
            title: report.title,
            body: body,
            labels: requestedLabels,
            submissionID: report.submissionID.uuidString,
            deviceID: report.deviceID,
            attachmentURLs: uploaded.map(\.url.absoluteString)
        )
        let response = try await client.postReport(request)

        guard let issueURL = URL(string: response.issueURL) else {
            throw GitTicketsError.payloadInvalid(reason: "Relay returned malformed issue URL")
        }

        // 5. Detect labels GitHub silently dropped so callers can fall back
        //    to title-prefix conventions / show a warning.
        let missingLabels = Self.missingLabels(requested: requestedLabels, applied: response.appliedLabels)
        if let missing = missingLabels, !missing.isEmpty {
            configuration.logger?.log(
                level: .warning,
                message: "Relay returned issue #\(response.issueNumber) but \(missing.count) requested label(s) were not applied: \(missing.joined(separator: ", ")).",
                error: nil
            )
        }

        let createdAt = Self.parseISO8601(response.createdAt) ?? clock()
        let submitted = SubmittedIssue(
            id: report.submissionID,
            issueNumber: response.issueNumber,
            issueURL: issueURL,
            title: response.title,
            createdAt: createdAt,
            missingLabels: missingLabels
        )

        // 6. Upsert into cache (best-effort — cache failures don't fail submission).
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
            do {
                try cache.upsert(record)
            } catch {
                configuration.logger?.log(
                    level: .warning,
                    message: "SubmissionCache upsert failed for #\(response.issueNumber); 'My Issues' will not show this submission until a successful resubmit.",
                    error: error
                )
            }
        }

        return submitted
    }

    // MARK: - Helpers

    /// One upload group's result — the optional screenshot URL plus the
    /// list of additional uploaded attachments.
    private struct UploadResult {
        let screenshotURL: URL?
        let attachments: [UploadedAttachment]
    }

    private func uploadAll(report: Report) async throws -> UploadResult {
        return try await withThrowingTaskGroup(of: (Int, ScreenshotOrAttachment).self) { group in
            // Index 0 is the screenshot (if any), 1..n are the attachments —
            // we sort by index so the rendered body keeps the same order as
            // `report.attachments` regardless of which finished first.
            var slots: [Int: ScreenshotOrAttachment] = [:]
            var count = 0
            if let screenshot = report.screenshot {
                let upload = ReportAttachment(filename: "screenshot.png", mimeType: "image/png", data: screenshot)
                let index = count
                count += 1
                group.addTask { [client] in
                    let response = try await client.uploadAttachment(upload)
                    guard let url = URL(string: response.url) else {
                        throw GitTicketsError.payloadInvalid(reason: "Relay returned malformed attachment URL")
                    }
                    return (index, .screenshot(url))
                }
            }
            for attachment in report.attachments {
                let index = count
                count += 1
                group.addTask { [client] in
                    let response = try await client.uploadAttachment(attachment)
                    guard let url = URL(string: response.url) else {
                        throw GitTicketsError.payloadInvalid(reason: "Relay returned malformed attachment URL")
                    }
                    return (index, .attachment(UploadedAttachment(
                        filename: attachment.filename,
                        url: url,
                        mimeType: attachment.mimeType
                    )))
                }
            }
            for try await pair in group {
                slots[pair.0] = pair.1
            }
            var screenshotURL: URL?
            var uploaded: [UploadedAttachment] = []
            for index in 0..<count {
                switch slots[index] {
                case .screenshot(let url):
                    screenshotURL = url
                case .attachment(let upload):
                    uploaded.append(upload)
                case .none:
                    break
                }
            }
            return UploadResult(screenshotURL: screenshotURL, attachments: uploaded)
        }
    }

    private enum ScreenshotOrAttachment {
        case screenshot(URL)
        case attachment(UploadedAttachment)
    }

    // MARK: - Phase 2 — My Issues + replies

    /// Fetches the relay's view of the supplied submissions and projects
    /// each match into a ``SubmittedIssue``. The local ``SubmissionCache``
    /// holds the canonical "read" state (the relay can't know whether the
    /// user has opened a reply on THIS device), so when a record is in
    /// cache we update its `replyCount` + `latestReplyAt` from the relay,
    /// upsert, and return the cache-derived projection (which carries the
    /// correct `unreadReplyCount`). Cache miss → return the wire-only
    /// projection.
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue] {
        guard !submissionIDs.isEmpty else { return [] }
        let request = MyIssuesRequest(
            submissionIDs: submissionIDs.map { $0.uuidString },
            deviceID: deviceID
        )
        let response = try await client.fetchMyIssues(request)
        return response.issues.compactMap { item -> SubmittedIssue? in
            guard let id = UUID(uuidString: item.submissionID) else { return nil }
            let wireProjection = Self.project(item)
            if let cache, var record = try? cache.record(submissionID: id) {
                record.replyCount = item.replyCount
                record.latestReplyAt = item.latestReplyAt.flatMap { Self.parseISO8601($0) }
                try? cache.upsert(record)
                return record.asSubmittedIssue
            }
            return wireProjection
        }
    }

    /// Cheap single-issue reply lookup. Delegates to the same `/my-issues`
    /// path as ``fetchMyIssues(submissionIDs:deviceID:)`` with a one-element
    /// list — the relay's API only exposes the list endpoint today, so this
    /// is the minimum-cost path.
    func fetchReplies(
        submissionID: UUID,
        deviceID: String
    ) async throws -> (replyCount: Int, latestReplyAt: Date?) {
        let issues = try await fetchMyIssues(submissionIDs: [submissionID], deviceID: deviceID)
        guard let match = issues.first(where: { $0.id == submissionID }) else {
            return (0, nil)
        }
        return (match.replyCount, match.latestReplyAt)
    }

    /// Wire-format → public ``SubmittedIssue`` projection. Returns nil when
    /// the relay response is malformed (bad UUID, unparseable URL) — the
    /// caller filters nils out rather than throwing partial-data errors
    /// across the API boundary.
    private static func project(_ item: MyIssuesItem) -> SubmittedIssue? {
        guard
            let id = UUID(uuidString: item.submissionID),
            let url = URL(string: item.issueURL),
            let createdAt = parseISO8601(item.createdAt)
        else { return nil }
        let latestReplyAt = item.latestReplyAt.flatMap { parseISO8601($0) }
        return SubmittedIssue(
            id: id,
            issueNumber: item.issueNumber,
            issueURL: url,
            title: item.title,
            createdAt: createdAt,
            latestReplyAt: latestReplyAt,
            replyCount: item.replyCount
        )
    }

    private static func validate(_ report: Report) throws {
        let trimmedTitle = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            throw GitTicketsError.payloadInvalid(reason: "Title is required")
        }
    }

    /// Returns the requested labels that the relay reports as not applied,
    /// or `nil` when the relay didn't include `appliedLabels` in the
    /// response. Comparison is case-insensitive — GitHub normalizes label
    /// case on the server side.
    static func missingLabels(requested: [String], applied: [String]?) -> [String]? {
        guard let applied else { return nil }
        let appliedNormalized = Set(applied.map { $0.lowercased() })
        let missing = requested.filter { !appliedNormalized.contains($0.lowercased()) }
        return missing
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
