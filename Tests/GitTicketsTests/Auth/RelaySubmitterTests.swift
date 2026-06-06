import XCTest
@testable import GitTickets

final class RelaySubmitterTests: XCTestCase {

    private let secret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))
    private let relayURL = URL(string: "https://relay.example.com")!

    private var dbURL: URL!
    private var cache: SubmissionCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.handlers.removeAll()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitTicketsSubmitterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("submissions.sqlite")
        cache = try SubmissionCache(databaseURL: dbURL)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.handlers.removeAll()
        cache = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
        try super.tearDownWithError()
    }

    private func makeSubmitter() -> RelaySubmitter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let http = HTTPClient(
            session: session,
            configuration: .init(maxAttempts: 1, baseBackoff: 0.001, maxBackoff: 0.01),
            userAgent: "Test/1.0"
        )
        let client = RelayClient(baseURL: relayURL, secret: secret, http: http, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let configuration = Configuration(
            repo: RepoCoordinate(owner: "alanw", name: "Test"),
            auth: .relay(url: relayURL, sharedSecret: secret)
        )
        return RelaySubmitter(
            configuration: configuration,
            client: client,
            cache: cache,
            userAgent: "Test/1.0",
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func makeReport(submissionID: UUID = UUID()) -> Report {
        Report(
            kind: .bug,
            title: "Crash on launch",
            body: "Tap the icon and the app crashes.",
            includeDiagnostics: true,
            diagnosticsBlob: "OS: macOS 26\nApp: Test 1.0",
            deviceID: "device-1",
            submissionID: submissionID
        )
    }

    // MARK: - Validation

    func test_emptyTitleRejected() async {
        let submitter = makeSubmitter()
        do {
            _ = try await submitter.submit(Report(kind: .bug, title: "   ", body: ""))
            XCTFail("Expected payloadInvalid")
        } catch GitTicketsError.payloadInvalid {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Happy path

    func test_happyPathPostsReportAndCaches() async throws {
        let report = makeReport()
        let reportURL = relayURL.appendingPathComponent("report")
        var capturedRequest: URLRequest?

        MockURLProtocol.handlers[reportURL] = { request in
            capturedRequest = request
            let response = RelayReportResponse(
                issueNumber: 42,
                issueURL: "https://github.com/alanw/Test/issues/42",
                title: "Crash on launch",
                createdAt: "2026-06-04T12:00:00Z",
                appliedLabels: ["bug", "gittickets"]
            )
            let data = try JSONEncoder().encode(response)
            return (
                HTTPURLResponse(url: reportURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
                data
            )
        }

        let submitted = try await makeSubmitter().submit(report)

        XCTAssertEqual(submitted.issueNumber, 42)
        XCTAssertEqual(submitted.issueURL.absoluteString, "https://github.com/alanw/Test/issues/42")
        XCTAssertEqual(submitted.id, report.submissionID)

        // Headers
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(capturedRequest?.value(forHTTPHeaderField: RelayClient.signatureHeader))
        XCTAssertNotNil(capturedRequest?.value(forHTTPHeaderField: RelayClient.timestampHeader))

        // Cache
        let cached = try XCTUnwrap(try cache.record(submissionID: report.submissionID))
        XCTAssertEqual(cached.issueNumber, 42)
        XCTAssertTrue(cached.body.contains("Tap the icon"))
        XCTAssertTrue(cached.body.contains("OS: macOS 26"), "diagnostics blob should be inlined")
        XCTAssertTrue(cached.body.contains(CorrelationMarker.render(for: report.submissionID)))
    }

    // MARK: - Diagnostics opt-out

    func test_includeDiagnosticsFalseOmitsBlob() async throws {
        var report = makeReport()
        report.includeDiagnostics = false

        let reportURL = relayURL.appendingPathComponent("report")
        var capturedBody: Data?
        MockURLProtocol.handlers[reportURL] = { request in
            capturedBody = request.httpBody ?? Self.bodyFromBodyStream(request)
            let response = RelayReportResponse(
                issueNumber: 1,
                issueURL: "https://github.com/x/y/issues/1",
                title: "t",
                createdAt: "2026-06-04T12:00:00Z",
                appliedLabels: nil
            )
            return (
                HTTPURLResponse(url: reportURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONEncoder().encode(response)
            )
        }

        _ = try await makeSubmitter().submit(report)
        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains("### Diagnostics"))
    }

    // MARK: - Attachments

    func test_screenshotUploadedBeforeReport() async throws {
        var report = makeReport()
        report.screenshot = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic

        let attachmentURL = relayURL.appendingPathComponent("attachment")
        let reportURL = relayURL.appendingPathComponent("report")
        var attachmentCalled = false
        var reportBody: String?

        MockURLProtocol.handlers[attachmentURL] = { _ in
            attachmentCalled = true
            let response = RelayAttachmentResponse(
                url: "https://relay/blob/abc.png",
                mimeType: "image/png",
                byteCount: 4
            )
            return (
                HTTPURLResponse(url: attachmentURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONEncoder().encode(response)
            )
        }
        MockURLProtocol.handlers[reportURL] = { request in
            reportBody = String(data: request.httpBody ?? Self.bodyFromBodyStream(request), encoding: .utf8)
            let response = RelayReportResponse(
                issueNumber: 1,
                issueURL: "https://x/y/1",
                title: "t",
                createdAt: "2026-06-04T12:00:00Z",
                appliedLabels: nil
            )
            return (
                HTTPURLResponse(url: reportURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONEncoder().encode(response)
            )
        }

        _ = try await makeSubmitter().submit(report)
        XCTAssertTrue(attachmentCalled)
        let body = reportBody ?? ""
        // The relay JSON encoder uses .withoutEscapingSlashes; some Foundation
        // pathways still escape — accept either.
        let containsURL = body.contains("https://relay/blob/abc.png")
            || body.contains("https:\\/\\/relay\\/blob\\/abc.png")
        XCTAssertTrue(containsURL, "Screenshot URL must be inlined into the issue body — body was: \(body.prefix(400))")
    }

    // MARK: - Error mapping

    func test_401MapsToSignatureMismatch() async {
        let reportURL = relayURL.appendingPathComponent("report")
        MockURLProtocol.handlers[reportURL] = { _ in
            (HTTPURLResponse(url: reportURL, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected signatureMismatch")
        } catch GitTicketsError.signatureMismatch {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_429MapsToRateLimitedWithRetryAfter() async {
        let reportURL = relayURL.appendingPathComponent("report")
        MockURLProtocol.handlers[reportURL] = { _ in
            (HTTPURLResponse(url: reportURL, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "60"])!, Data())
        }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected rateLimited")
        } catch GitTicketsError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 60)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_413MapsToAttachmentTooLarge() async {
        var report = makeReport()
        report.screenshot = Data([0xFF])
        let attachmentURL = relayURL.appendingPathComponent("attachment")
        MockURLProtocol.handlers[attachmentURL] = { _ in
            (HTTPURLResponse(url: attachmentURL, statusCode: 413, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeSubmitter().submit(report)
            XCTFail("Expected attachmentTooLarge")
        } catch GitTicketsError.attachmentTooLarge {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_500MapsToRelayRejected() async {
        let reportURL = relayURL.appendingPathComponent("report")
        let envelope = RelayErrorEnvelope(error: "internal", message: "kaboom", byteLimit: nil)
        let data = try! JSONEncoder().encode(envelope)
        MockURLProtocol.handlers[reportURL] = { _ in
            (HTTPURLResponse(url: reportURL, statusCode: 500, httpVersion: nil, headerFields: nil)!, data)
        }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected relayRejected")
        } catch GitTicketsError.relayRejected(let status, let message) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(message, "kaboom")
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Dropped-labels detection (C22)

    func test_relayDroppedLabelsSurfaceInMissingLabels() async throws {
        let reportURL = relayURL.appendingPathComponent("report")
        MockURLProtocol.handlers[reportURL] = { _ in
            // Relay only confirms `bug` — `gittickets` was silently dropped.
            let response = RelayReportResponse(
                issueNumber: 1,
                issueURL: "https://x/y/1",
                title: "t",
                createdAt: "2026-06-04T12:00:00Z",
                appliedLabels: ["bug"]
            )
            return (
                HTTPURLResponse(url: reportURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONEncoder().encode(response)
            )
        }
        let submitted = try await makeSubmitter().submit(makeReport())
        XCTAssertEqual(submitted.missingLabels, ["gittickets"])
    }

    func test_nilAppliedLabelsLeavesMissingLabelsNil() async throws {
        let reportURL = relayURL.appendingPathComponent("report")
        MockURLProtocol.handlers[reportURL] = { _ in
            let response = RelayReportResponse(
                issueNumber: 1,
                issueURL: "https://x/y/1",
                title: "t",
                createdAt: "2026-06-04T12:00:00Z",
                appliedLabels: nil
            )
            return (
                HTTPURLResponse(url: reportURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONEncoder().encode(response)
            )
        }
        let submitted = try await makeSubmitter().submit(makeReport())
        XCTAssertNil(submitted.missingLabels)
    }

    // MARK: - Pre-submission cache dedupe (C4)

    func test_cachedSubmissionIsReturnedWithoutHittingRelay() async throws {
        let report = makeReport()
        // Seed the cache directly.
        let preExisting = SubmissionRecord(
            submissionID: report.submissionID,
            issueNumber: 99,
            issueURL: URL(string: "https://github.com/x/y/issues/99")!,
            title: "Already filed",
            kind: .bug,
            body: "Cached body",
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try cache.upsert(preExisting)

        let reportURL = relayURL.appendingPathComponent("report")
        var relayCalled = false
        MockURLProtocol.handlers[reportURL] = { _ in
            relayCalled = true
            return (HTTPURLResponse(url: reportURL, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let submitted = try await makeSubmitter().submit(report)
        XCTAssertFalse(relayCalled, "cache hit must short-circuit the network path")
        XCTAssertEqual(submitted.issueNumber, 99)
    }

    // MARK: - ISO8601 parser

    func test_parseISO8601WithAndWithoutFractional() {
        XCTAssertNotNil(RelaySubmitter.parseISO8601("2026-06-04T12:00:00Z"))
        XCTAssertNotNil(RelaySubmitter.parseISO8601("2026-06-04T12:00:00.123Z"))
        XCTAssertNil(RelaySubmitter.parseISO8601("not a date"))
    }

    // MARK: - Phase 2 — fetchMyIssues / fetchReplies

    /// Regression: RelaySubmitter used to inherit the protocol's
    /// throws-not-supported default for fetchMyIssues — same shape as the
    /// pre-fix submit() bug. This test locks the real wiring.
    func test_fetchMyIssuesPostsToRelayAndMergesWithCache() async throws {
        let id = UUID()
        let myIssuesURL = relayURL.appendingPathComponent("my-issues")
        MockURLProtocol.handlers[myIssuesURL] = { _ in
            let response = MyIssuesResponse(issues: [
                MyIssuesItem(
                    submissionID: id.uuidString,
                    issueNumber: 7,
                    issueURL: "https://github.com/x/y/issues/7",
                    title: "Updated title",
                    state: "open",
                    createdAt: "2026-06-04T12:00:00Z",
                    updatedAt: "2026-06-05T13:00:00Z",
                    replyCount: 3,
                    latestReplyAt: "2026-06-05T13:00:00Z"
                )
            ])
            let data = try RelayJSON.encoder.encode(response)
            return (HTTPURLResponse(url: myIssuesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        // Seed the cache with an existing record so the merge path runs.
        let seeded = SubmissionRecord(
            submissionID: id,
            issueNumber: 7,
            issueURL: URL(string: "https://github.com/x/y/issues/7")!,
            title: "Original title",
            kind: .bug,
            body: "seed",
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_700_000_000),
            latestReplyAt: nil,
            replyCount: 0,
            readReplyCount: 1
        )
        try cache.upsert(seeded)

        let issues = try await makeSubmitter().fetchMyIssues(
            submissionIDs: [id],
            deviceID: "device-1"
        )

        XCTAssertEqual(issues.count, 1)
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.id, id)
        XCTAssertEqual(issue.replyCount, 3)
        // unreadReplyCount = max(0, 3 - 1) = 2 via cache merge.
        XCTAssertEqual(issue.unreadReplyCount, 2)

        // Cache should now carry the latest reply state.
        let updated = try XCTUnwrap(try cache.record(submissionID: id))
        XCTAssertEqual(updated.replyCount, 3)
        XCTAssertNotNil(updated.latestReplyAt)
        // Read state must NOT have been clobbered.
        XCTAssertEqual(updated.readReplyCount, 1)
    }

    func test_fetchMyIssuesEmptyInputShortCircuits() async throws {
        // No handler registered — if the submitter doesn't short-circuit, the
        // MockURLProtocol fallback throws .unsupportedURL.
        let issues = try await makeSubmitter().fetchMyIssues(
            submissionIDs: [],
            deviceID: "device-1"
        )
        XCTAssertTrue(issues.isEmpty)
    }

    func test_fetchRepliesDelegatesToMyIssues() async throws {
        let id = UUID()
        let myIssuesURL = relayURL.appendingPathComponent("my-issues")
        var capturedBody: Data?
        MockURLProtocol.handlers[myIssuesURL] = { request in
            capturedBody = request.httpBody ?? Self.bodyFromBodyStream(request)
            let response = MyIssuesResponse(issues: [
                MyIssuesItem(
                    submissionID: id.uuidString,
                    issueNumber: 9,
                    issueURL: "https://github.com/x/y/issues/9",
                    title: "t",
                    state: "open",
                    createdAt: "2026-06-04T12:00:00Z",
                    updatedAt: "2026-06-04T13:00:00Z",
                    replyCount: 5,
                    latestReplyAt: "2026-06-04T13:00:00Z"
                )
            ])
            let data = try RelayJSON.encoder.encode(response)
            return (HTTPURLResponse(url: myIssuesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let result = try await makeSubmitter().fetchReplies(
            submissionID: id,
            deviceID: "device-1"
        )
        XCTAssertEqual(result.replyCount, 5)
        XCTAssertNotNil(result.latestReplyAt)
        // The relay request body should carry exactly one submission ID.
        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains(id.uuidString.uppercased())
                      || bodyString.contains(id.uuidString.lowercased()))
    }

    func test_fetchRepliesUnknownSubmissionReturnsZero() async throws {
        let myIssuesURL = relayURL.appendingPathComponent("my-issues")
        MockURLProtocol.handlers[myIssuesURL] = { _ in
            let response = MyIssuesResponse(issues: [])
            let data = try RelayJSON.encoder.encode(response)
            return (HTTPURLResponse(url: myIssuesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let result = try await makeSubmitter().fetchReplies(
            submissionID: UUID(),
            deviceID: "device-1"
        )
        XCTAssertEqual(result.replyCount, 0)
        XCTAssertNil(result.latestReplyAt)
    }

    // MARK: - Helpers

    private static func bodyFromBodyStream(_ request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
