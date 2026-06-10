import XCTest
@testable import GitTickets

final class DeviceFlowSubmitterTests: XCTestCase {

    private let apiBaseURL = URL(string: "https://api.github.test")!

    private var tokenService: String!
    private var tokenStore: TokenStore!
    private var dbURL: URL!
    private var cache: SubmissionCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(simulator) && os(iOS)
        // iOS Sim XCTest bundles lack keychain-access-groups entitlement; the
        // TokenStore writes below would fail with errSecMissingEntitlement
        // (-34018). Covered on the macOS test job and on real devices. See:
        // .memory/footguns/footgun-ios-sim-xctest-has-no-keychain-entitlement.md
        throw XCTSkip("Keychain unavailable in iOS Simulator SPM test bundle")
        #endif
        MockURLProtocol.handlers.removeAll()

        tokenService = "com.gittickets.tests.df-submitter.\(UUID().uuidString)"
        tokenStore = TokenStore(service: tokenService)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitTicketsDFSubmitterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("submissions.sqlite")
        cache = try SubmissionCache(databaseURL: dbURL)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.handlers.removeAll()
        // `tokenService` is left nil on iOS Sim because setUpWithError throws
        // XCTSkip before assigning it.
        if let tokenService {
            try? Keychain.delete(service: tokenService, account: TokenStore.defaultAccount)
        }
        cache = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
        try super.tearDownWithError()
    }

    // MARK: - Test rig

    private func makeSubmitter() -> DeviceFlowSubmitter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let http = HTTPClient(
            session: session,
            configuration: .init(maxAttempts: 1, baseBackoff: 0.001, maxBackoff: 0.01),
            userAgent: "Test/1.0"
        )
        let configuration = Configuration(
            repo: RepoCoordinate(owner: "alanw", name: "Test"),
            auth: .deviceFlow(clientID: "Iv1.test", scopes: [.publicRepo])
        )
        return DeviceFlowSubmitter(
            configuration: configuration,
            tokenStore: tokenStore,
            cache: cache,
            http: http,
            userAgent: "Test/1.0",
            apiBaseURL: apiBaseURL,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )!
    }

    private func makeReport(
        submissionID: UUID = UUID(),
        screenshot: Data? = nil,
        attachments: [ReportAttachment] = []
    ) -> Report {
        Report(
            kind: .bug,
            title: "Crash on launch",
            body: "Tap the icon and the app crashes.",
            screenshot: screenshot,
            attachments: attachments,
            includeDiagnostics: true,
            diagnosticsBlob: "OS: macOS 26\nApp: Test 1.0",
            deviceID: "device-1",
            submissionID: submissionID
        )
    }

    private func issuesURL() -> URL {
        apiBaseURL
            .appendingPathComponent("/repos")
            .appendingPathComponent("alanw")
            .appendingPathComponent("Test")
            .appendingPathComponent("/issues")
    }

    private func okJSON(_ url: URL, _ json: String, code: Int = 201) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
            Data(json.utf8)
        )
    }

    private func status(_ url: URL, _ code: Int, headers: [String: String]? = nil, body: Data = Data()) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!, body)
    }

    private func happyResponseJSON(number: Int = 42, labels: [String] = ["bug", "gittickets"]) -> String {
        let labelsJSON = labels.map { #""\#($0)""# }.map { #"{"name":\#($0)}"# }.joined(separator: ",")
        return """
        {
          "number": \(number),
          "html_url": "https://github.com/alanw/Test/issues/\(number)",
          "title": "Crash on launch",
          "created_at": "2026-06-04T12:00:00Z",
          "labels": [\(labelsJSON)]
        }
        """
    }

    // MARK: - Validation

    func test_emptyTitleRejected() async throws {
        try tokenStore.write("gho_test")
        let submitter = makeSubmitter()
        do {
            _ = try await submitter.submit(Report(kind: .bug, title: "   ", body: ""))
            XCTFail("Expected payloadInvalid")
        } catch GitTicketsError.payloadInvalid {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_screenshotRejected() async throws {
        try tokenStore.write("gho_test")
        let submitter = makeSubmitter()
        let report = makeReport(screenshot: Data([0x89, 0x50, 0x4E, 0x47]))
        do {
            _ = try await submitter.submit(report)
            XCTFail("Expected attachmentNotSupportedInDeviceFlow")
        } catch GitTicketsError.attachmentNotSupportedInDeviceFlow {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_attachmentsRejected() async throws {
        try tokenStore.write("gho_test")
        let submitter = makeSubmitter()
        let attachment = ReportAttachment(filename: "log.txt", mimeType: "text/plain", data: Data("x".utf8))
        let report = makeReport(attachments: [attachment])
        do {
            _ = try await submitter.submit(report)
            XCTFail("Expected attachmentNotSupportedInDeviceFlow")
        } catch GitTicketsError.attachmentNotSupportedInDeviceFlow {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Authorization

    func test_missingTokenThrowsDeviceFlowNotAuthorized() async {
        // Store deliberately empty.
        let submitter = makeSubmitter()
        do {
            _ = try await submitter.submit(makeReport())
            XCTFail("Expected deviceFlowNotAuthorized")
        } catch GitTicketsError.deviceFlowNotAuthorized {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Happy path

    func test_happyPathPostsIssueAndCaches() async throws {
        try tokenStore.write("gho_happy")
        let report = makeReport()
        let url = issuesURL()
        var captured: URLRequest?
        MockURLProtocol.handlers[url] = { request in
            captured = request
            return self.okJSON(url, self.happyResponseJSON())
        }

        let submitted = try await makeSubmitter().submit(report)

        XCTAssertEqual(submitted.issueNumber, 42)
        XCTAssertEqual(submitted.issueURL.absoluteString, "https://github.com/alanw/Test/issues/42")
        XCTAssertEqual(submitted.id, report.submissionID)
        XCTAssertEqual(submitted.missingLabels, [])

        // Headers
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer gho_happy")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // Body — must carry the user body and the diagnostics blob.
        let bodyData = captured?.httpBody ?? Self.bodyFromBodyStream(captured!)
        let bodyStr = String(data: bodyData, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyStr.contains("Tap the icon"))
        XCTAssertTrue(bodyStr.contains("OS: macOS 26"))
        XCTAssertTrue(bodyStr.contains(CorrelationMarker.render(for: report.submissionID)))

        // Cache
        let cached = try XCTUnwrap(try cache.record(submissionID: report.submissionID))
        XCTAssertEqual(cached.issueNumber, 42)
        XCTAssertTrue(cached.body.contains("Tap the icon"))
    }

    func test_missingLabelsSurface() async throws {
        try tokenStore.write("gho_test")
        let url = issuesURL()
        MockURLProtocol.handlers[url] = { _ in
            // Only `bug` came back — `gittickets` was silently dropped by GitHub
            // because the Device Flow user lacks Issues: write on the repo.
            self.okJSON(url, self.happyResponseJSON(labels: ["bug"]))
        }
        let submitted = try await makeSubmitter().submit(makeReport())
        XCTAssertEqual(submitted.missingLabels, ["gittickets"])
    }

    // MARK: - Error mapping

    func test_401WipesTokenAndThrowsNotAuthorized() async throws {
        try tokenStore.write("gho_dead")
        let url = issuesURL()
        MockURLProtocol.handlers[url] = { _ in self.status(url, 401) }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected deviceFlowNotAuthorized")
        } catch GitTicketsError.deviceFlowNotAuthorized {
            // expected — and the dead token must be cleared so the next attempt re-prompts.
            XCTAssertNil(try tokenStore.read(), "401 must wipe the stored token")
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_403MapsToRateLimited() async throws {
        try tokenStore.write("gho_test")
        let url = issuesURL()
        MockURLProtocol.handlers[url] = { _ in self.status(url, 403, headers: ["Retry-After": "120"]) }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected rateLimited")
        } catch GitTicketsError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_429MapsToRateLimited() async throws {
        try tokenStore.write("gho_test")
        let url = issuesURL()
        MockURLProtocol.handlers[url] = { _ in self.status(url, 429, headers: ["Retry-After": "60"]) }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected rateLimited")
        } catch GitTicketsError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 60)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_422MapsToPayloadInvalid() async throws {
        try tokenStore.write("gho_test")
        let url = issuesURL()
        let envelope = #"{"message":"Validation Failed","documentation_url":"https://docs.github.com"}"#
        MockURLProtocol.handlers[url] = { _ in
            self.status(url, 422, body: Data(envelope.utf8))
        }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected payloadInvalid")
        } catch GitTicketsError.payloadInvalid(let reason) {
            XCTAssertTrue(reason.contains("Validation Failed"))
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_500MapsToRelayRejected() async throws {
        try tokenStore.write("gho_test")
        let url = issuesURL()
        let envelope = #"{"message":"GitHub down"}"#
        MockURLProtocol.handlers[url] = { _ in self.status(url, 500, body: Data(envelope.utf8)) }
        do {
            _ = try await makeSubmitter().submit(makeReport())
            XCTFail("Expected relayRejected")
        } catch GitTicketsError.relayRejected(let code, let message) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(message, "GitHub down")
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Cache dedupe

    func test_cachedSubmissionShortCircuits() async throws {
        try tokenStore.write("gho_test")
        let report = makeReport()
        let preExisting = SubmissionRecord(
            submissionID: report.submissionID,
            issueNumber: 99,
            issueURL: URL(string: "https://github.com/alanw/Test/issues/99")!,
            title: "Already filed",
            kind: .bug,
            body: "Cached body",
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try cache.upsert(preExisting)

        let url = issuesURL()
        var hit = false
        MockURLProtocol.handlers[url] = { _ in
            hit = true
            return self.status(url, 500)
        }

        let submitted = try await makeSubmitter().submit(report)
        XCTAssertFalse(hit, "cache hit must short-circuit the network")
        XCTAssertEqual(submitted.issueNumber, 99)
    }

    // MARK: - PR 15 — fetchMyIssues + fetchComments

    private func issueURL(_ number: Int) -> URL {
        apiBaseURL
            .appendingPathComponent("/repos")
            .appendingPathComponent("alanw")
            .appendingPathComponent("Test")
            .appendingPathComponent("/issues")
            .appendingPathComponent(String(number))
    }

    private func commentsURL(_ number: Int) -> URL {
        issueURL(number).appendingPathComponent("/comments")
    }

    func test_fetchMyIssuesUpdatesCacheFromGitHubGet() async throws {
        try tokenStore.write("gho_test")
        let id = UUID()
        // Seed cache so the device-flow path has a known issueNumber to GET.
        let seeded = SubmissionRecord(
            submissionID: id,
            issueNumber: 7,
            issueURL: URL(string: "https://github.com/alanw/Test/issues/7")!,
            title: "Old title",
            kind: .bug,
            body: "seed body",
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_700_000_000),
            latestReplyAt: nil,
            replyCount: 0,
            readReplyCount: 0
        )
        try cache.upsert(seeded)

        MockURLProtocol.handlers[issueURL(7)] = { _ in
            let body = #"""
            {"title":"Refreshed title","comments":4,"updated_at":"2026-06-05T13:00:00Z"}
            """#
            return self.okJSON(self.issueURL(7), body, code: 200)
        }

        let issues = try await makeSubmitter().fetchMyIssues(submissionIDs: [id], deviceID: "device-1")
        XCTAssertEqual(issues.count, 1)
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.title, "Refreshed title")
        XCTAssertEqual(issue.replyCount, 4)
        XCTAssertNotNil(issue.latestReplyAt)

        // Cache should now carry the refreshed metadata.
        let updated = try XCTUnwrap(try cache.record(submissionID: id))
        XCTAssertEqual(updated.title, "Refreshed title")
        XCTAssertEqual(updated.replyCount, 4)
        // readReplyCount is local state — must NOT be clobbered by the refresh.
        XCTAssertEqual(updated.readReplyCount, 0)
    }

    func test_fetchMyIssuesNoTokenThrowsNotAuthorized() async {
        // Even with a seeded cache, missing token should throw before any
        // HTTP — so the form can present the auth sheet.
        let id = UUID()
        let seeded = SubmissionRecord(
            submissionID: id,
            issueNumber: 1,
            issueURL: URL(string: "https://github.com/alanw/Test/issues/1")!,
            title: "x",
            kind: .bug,
            body: "x",
            deviceID: "device-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try? cache.upsert(seeded)
        do {
            _ = try await makeSubmitter().fetchMyIssues(submissionIDs: [id], deviceID: "device-1")
            XCTFail("Expected deviceFlowNotAuthorized")
        } catch GitTicketsError.deviceFlowNotAuthorized {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_fetchCommentsRoundTrips() async throws {
        try tokenStore.write("gho_test")
        let url = commentsURL(42)
        MockURLProtocol.handlers[url] = { _ in
            let body = #"""
            [
              {"id":100,"body":"Got it.","created_at":"2026-06-04T13:00:00Z","user":{"login":"maintainer"}},
              {"id":101,"body":"Thanks!","created_at":"2026-06-04T14:00:00Z","user":{"login":"reporter"}}
            ]
            """#
            return self.okJSON(url, body, code: 200)
        }

        let comments = try await makeSubmitter().fetchComments(issueNumber: 42, deviceID: "device-1")
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].author, "maintainer")
        XCTAssertEqual(comments[0].body, "Got it.")
        XCTAssertEqual(comments[1].author, "reporter")
    }

    func test_fetchComments401WipesToken() async throws {
        try tokenStore.write("gho_dead")
        let url = commentsURL(7)
        MockURLProtocol.handlers[url] = { _ in self.status(url, 401) }
        do {
            _ = try await makeSubmitter().fetchComments(issueNumber: 7, deviceID: "d")
            XCTFail("Expected deviceFlowNotAuthorized")
        } catch GitTicketsError.deviceFlowNotAuthorized {
            XCTAssertNil(try tokenStore.read(), "401 on comments must wipe the dead token")
        } catch {
            XCTFail("Unexpected: \(error)")
        }
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
