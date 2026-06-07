import Foundation

/// The Device Flow submitter — posts to the GitHub Issues API directly using an OAuth token
/// obtained via ``DeviceFlowCoordinator``. Mirrors ``RelaySubmitter`` step-for-step except:
///
/// - No attachment surface (GitHub has no public attachment upload API and Device Flow has no
///   relay-side storage). `report.screenshot` / `report.attachments` non-empty → throws
///   ``GitTicketsError/attachmentNotSupportedInDeviceFlow``.
/// - Authenticates with `Authorization: Bearer <token>` from ``TokenStore`` instead of HMAC.
/// - 401 from the Issues API means the token was revoked server-side; the submitter deletes the
///   stored token and throws ``GitTicketsError/deviceFlowNotAuthorized`` so the form re-prompts.
///
/// Concurrency: `Sendable` and stateless beyond injected dependencies.
struct DeviceFlowSubmitter: IssueSubmitter {

    let configuration: Configuration
    let clientID: String
    let scopes: [DeviceFlowScope]
    let http: HTTPClient
    let tokenStore: TokenStore
    let cache: SubmissionCache?
    let userAgent: String
    let clock: @Sendable () -> Date
    let apiBaseURL: URL

    /// Standard GitHub API host. Overridden in tests so MockURLProtocol can intercept.
    static let defaultAPIBaseURL = URL(string: "https://api.github.com")!

    init?(
        configuration: Configuration,
        tokenStore: TokenStore = TokenStore(),
        cache: SubmissionCache? = nil,
        http: HTTPClient? = nil,
        userAgent: String = UserAgent.string(),
        apiBaseURL: URL = DeviceFlowSubmitter.defaultAPIBaseURL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        guard case let .deviceFlow(clientID, scopes) = configuration.auth else { return nil }
        self.configuration = configuration
        self.clientID = clientID
        self.scopes = scopes
        self.http = http ?? HTTPClient(userAgent: userAgent)
        self.tokenStore = tokenStore
        self.cache = cache
        self.userAgent = userAgent
        self.apiBaseURL = apiBaseURL
        self.clock = clock
    }

    func submit(_ report: Report) async throws -> SubmittedIssue {
        try Self.validate(report)

        // Cache dedupe — same shape as RelaySubmitter, protects against UI double-tap and
        // any caller-side retry that we couldn't safely retry at the HTTP layer.
        if let cache,
           let existing = try? cache.record(submissionID: report.submissionID) {
            return existing.asSubmittedIssue
        }

        guard let token = try readToken() else {
            throw GitTicketsError.deviceFlowNotAuthorized
        }

        // Device Flow has no attachment storage. Build the body with no screenshot / no
        // uploaded attachments — IssueBodyBuilder skips those sections when their inputs
        // are nil/empty.
        let body = IssueBodyBuilder.build(
            report: report,
            diagnostics: report.includeDiagnostics ? report.diagnosticsBlob : nil,
            screenshotURL: nil,
            attachments: []
        )
        let requestedLabels = BodyTemplates.defaultLabels(for: report.kind) + [configuration.myIssues.label]
        let payload = CreateIssueRequest(title: report.title, body: body, labels: requestedLabels)
        let encoded: Data
        do {
            encoded = try DeviceFlowJSON.encoder.encode(payload)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not encode create-issue payload: \(error)")
        }

        let response = try await postIssue(token: token, body: encoded)
        try validateIssueResponse(response)
        let decoded: CreateIssueResponse
        do {
            decoded = try DeviceFlowJSON.decoder.decode(CreateIssueResponse.self, from: response.body)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not decode create-issue response: \(error)")
        }

        guard let issueURL = URL(string: decoded.htmlURL) else {
            throw GitTicketsError.payloadInvalid(reason: "GitHub returned malformed html_url")
        }

        // Re-use RelaySubmitter's label diff so the two submitters surface dropped labels the
        // same way — same shape, same `missingLabels: nil` semantics for "unknown."
        let appliedLabels = decoded.labels.map(\.name)
        let missing = RelaySubmitter.missingLabels(requested: requestedLabels, applied: appliedLabels)
        if let missing, !missing.isEmpty {
            configuration.logger?.log(
                level: .warning,
                message: "GitHub created issue #\(decoded.number) but \(missing.count) requested label(s) were dropped: \(missing.joined(separator: ", ")). Device Flow users without Issues: write often hit this.",
                error: nil
            )
        }

        let createdAt = RelaySubmitter.parseISO8601(decoded.createdAt) ?? clock()
        let submitted = SubmittedIssue(
            id: report.submissionID,
            issueNumber: decoded.number,
            issueURL: issueURL,
            title: decoded.title,
            createdAt: createdAt,
            missingLabels: missing
        )

        if let cache {
            let record = SubmissionRecord(
                submissionID: report.submissionID,
                issueNumber: decoded.number,
                issueURL: issueURL,
                title: decoded.title,
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
                    message: "SubmissionCache upsert failed for #\(decoded.number); 'My Issues' will not show this submission until a successful resubmit.",
                    error: error
                )
            }
        }

        return submitted
    }

    // MARK: - Validation + token read

    private static func validate(_ report: Report) throws {
        let trimmed = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw GitTicketsError.payloadInvalid(reason: "Title is required")
        }
        if report.screenshot != nil || !report.attachments.isEmpty {
            throw GitTicketsError.attachmentNotSupportedInDeviceFlow
        }
    }

    private func readToken() throws -> String? {
        do {
            return try tokenStore.read()
        } catch {
            // A Keychain read failure mid-submit is the same UX as "no token" — the form
            // will drive the user back through Device Flow. Logging so adopters can diagnose
            // recurring Keychain failures from log inspection.
            configuration.logger?.log(
                level: .warning,
                message: "TokenStore read failed; treating as deviceFlowNotAuthorized.",
                error: error
            )
            return nil
        }
    }

    // MARK: - HTTP

    private func postIssue(token: String, body: Data) async throws -> HTTPResponse {
        let url = apiBaseURL
            .appendingPathComponent("/repos")
            .appendingPathComponent(configuration.repo.owner)
            .appendingPathComponent(configuration.repo.name)
            .appendingPathComponent("/issues")
        do {
            return try await http.sendRetrying { _ in
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.httpBody = body
                return req
            }
        } catch {
            throw GitTicketsError.relayUnreachable(underlying: error)
        }
    }

    // MARK: - Phase 2 — fetchMyIssues + fetchComments

    /// Pulls fresh state for the supplied submissions out of the user's own
    /// issues. The cache holds the canonical `submissionID → issueNumber`
    /// mapping (we created the issue, so we know its number); the GitHub
    /// Issues API gives us the current title / comment count / latest update.
    ///
    /// One `GET /repos/:owner/:name/issues/:n` per submission. With manual
    /// refresh as the v1 default, this is a few requests at most — cheap
    /// compared to walking GitHub Search.
    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue] {
        guard !submissionIDs.isEmpty else { return [] }
        guard let token = try readToken() else {
            throw GitTicketsError.deviceFlowNotAuthorized
        }
        guard let cache else { return [] }

        var results: [SubmittedIssue] = []
        for id in submissionIDs {
            guard let record = try? cache.record(submissionID: id) else { continue }
            do {
                let issue = try await getIssue(number: record.issueNumber, token: token)
                // `title` on SubmissionRecord is `let` (the row's submit-time
                // snapshot); rebuild rather than mutate so a future title rename
                // on GitHub propagates without changing the record's public surface.
                let updated = SubmissionRecord(
                    submissionID: record.submissionID,
                    issueNumber: record.issueNumber,
                    issueURL: record.issueURL,
                    title: issue.title,
                    kind: record.kind,
                    body: record.body,
                    deviceID: record.deviceID,
                    createdAt: record.createdAt,
                    submittedAt: record.submittedAt,
                    latestReplyAt: issue.latestReplyAt,
                    replyCount: issue.replyCount,
                    readReplyCount: record.readReplyCount
                )
                try? cache.upsert(updated)
                results.append(updated.asSubmittedIssue)
            } catch GitTicketsError.deviceFlowNotAuthorized {
                throw GitTicketsError.deviceFlowNotAuthorized
            } catch {
                configuration.logger?.log(
                    level: .warning,
                    message: "Device Flow fetchMyIssues failed for #\(record.issueNumber); returning cached projection.",
                    error: error
                )
                results.append(record.asSubmittedIssue)
            }
        }
        return results
    }

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

    /// Fetches the comment thread for one issue via
    /// `GET /repos/:owner/:name/issues/:n/comments`. Ordered oldest first to
    /// match the relay path's contract.
    func fetchComments(issueNumber: Int, deviceID: String) async throws -> [IssueComment] {
        guard let token = try readToken() else {
            throw GitTicketsError.deviceFlowNotAuthorized
        }
        let url = apiBaseURL
            .appendingPathComponent("/repos")
            .appendingPathComponent(configuration.repo.owner)
            .appendingPathComponent(configuration.repo.name)
            .appendingPathComponent("/issues")
            .appendingPathComponent(String(issueNumber))
            .appendingPathComponent("/comments")
        let response = try await getJSON(url: url, token: token)
        try validateIssueResponse(response)
        let decoded: [GitHubComment]
        do {
            decoded = try DeviceFlowJSON.decoder.decode([GitHubComment].self, from: response.body)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not decode comments response: \(error)")
        }
        return decoded.compactMap { wire -> IssueComment? in
            guard let createdAt = RelaySubmitter.parseISO8601(wire.createdAt) else { return nil }
            return IssueComment(
                id: wire.id,
                author: wire.user?.login ?? "",
                body: wire.body ?? "",
                createdAt: createdAt
            )
        }
    }

    // MARK: - GitHub GET helpers

    private struct GitHubIssue {
        let title: String
        let replyCount: Int
        let latestReplyAt: Date?
    }

    private func getIssue(number: Int, token: String) async throws -> GitHubIssue {
        let url = apiBaseURL
            .appendingPathComponent("/repos")
            .appendingPathComponent(configuration.repo.owner)
            .appendingPathComponent(configuration.repo.name)
            .appendingPathComponent("/issues")
            .appendingPathComponent(String(number))
        let response = try await getJSON(url: url, token: token)
        try validateIssueResponse(response)
        let wire: GitHubIssueResponse
        do {
            wire = try DeviceFlowJSON.decoder.decode(GitHubIssueResponse.self, from: response.body)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not decode issue response: \(error)")
        }
        return GitHubIssue(
            title: wire.title,
            replyCount: wire.comments,
            latestReplyAt: wire.updatedAt.flatMap { RelaySubmitter.parseISO8601($0) }
        )
    }

    private func getJSON(url: URL, token: String) async throws -> HTTPResponse {
        do {
            return try await http.sendRetrying { _ in
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
        } catch {
            throw GitTicketsError.relayUnreachable(underlying: error)
        }
    }

    // MARK: - GitHub wire types

    private struct GitHubIssueResponse: Decodable {
        let title: String
        let comments: Int
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case title
            case comments
            case updatedAt = "updated_at"
        }
    }

    private struct GitHubComment: Decodable {
        let id: Int
        let body: String?
        let createdAt: String
        let user: GitHubUser?

        enum CodingKeys: String, CodingKey {
            case id
            case body
            case createdAt = "created_at"
            case user
        }
    }

    private struct GitHubUser: Decodable {
        let login: String
    }

    /// Maps GitHub Issues API status codes to ``GitTicketsError``. 401 is the load-bearing
    /// case: it means the token was revoked, so we wipe local storage and surface
    /// `.deviceFlowNotAuthorized` to force a fresh sign-in — leaving the dead token in place
    /// would have every future submit() fail the same way until the user reinstalls.
    private func validateIssueResponse(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            try? tokenStore.delete()
            throw GitTicketsError.deviceFlowNotAuthorized
        case 403, 429:
            let retryAfter = response.header("Retry-After").flatMap { RateLimitBackoff.parseRetryAfter($0) }
            throw GitTicketsError.rateLimited(retryAfter: retryAfter)
        case 422:
            let envelope = try? DeviceFlowJSON.decoder.decode(GitHubErrorEnvelope.self, from: response.body)
            throw GitTicketsError.payloadInvalid(reason: envelope?.message ?? "GitHub rejected the payload")
        default:
            let envelope = try? DeviceFlowJSON.decoder.decode(GitHubErrorEnvelope.self, from: response.body)
            throw GitTicketsError.relayRejected(statusCode: response.statusCode, message: envelope?.message)
        }
    }
}
