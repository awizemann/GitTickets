import XCTest
@testable import GitTickets

final class DeviceFlowCoordinatorTests: XCTestCase {

    private let baseURL = URL(string: "https://github.test")!
    private let clientID = "Iv1.test"

    override func setUp() {
        super.setUp()
        MockURLProtocol.handlers.removeAll()
    }

    override func tearDown() {
        MockURLProtocol.handlers.removeAll()
        super.tearDown()
    }

    // MARK: - Test rig

    private func makeCoordinator(
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> DeviceFlowCoordinator {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let http = HTTPClient(
            session: session,
            configuration: .init(maxAttempts: 1, baseBackoff: 0.001, maxBackoff: 0.01),
            userAgent: "Test/1.0"
        )
        return DeviceFlowCoordinator(
            clientID: clientID,
            scopes: [.publicRepo],
            http: http,
            baseURL: baseURL,
            clock: clock,
            sleep: { _ in /* fast-forward */ }
        )
    }

    private func deviceCodeURL() -> URL {
        baseURL.appendingPathComponent("/login/device/code")
    }

    private func accessTokenURL() -> URL {
        baseURL.appendingPathComponent("/login/oauth/access_token")
    }

    private func okJSON(_ url: URL, _ json: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
            Data(json.utf8)
        )
    }

    private func status(_ url: URL, _ code: Int, headers: [String: String]? = nil, body: Data = Data()) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!, body)
    }

    // MARK: - requestAuthorization

    func test_requestAuthorizationReturnsCodeAndDeadline() async throws {
        let url = deviceCodeURL()
        var capturedBody: Data?
        MockURLProtocol.handlers[url] = { req in
            capturedBody = req.httpBody ?? Self.bodyFromBodyStream(req)
            return self.okJSON(url, """
            {
              "device_code": "DEV-CODE-XYZ",
              "user_code": "ABCD-1234",
              "verification_uri": "https://github.com/login/device",
              "verification_uri_complete": "https://github.com/login/device?user_code=ABCD-1234",
              "expires_in": 900,
              "interval": 5
            }
            """)
        }

        let coordinator = makeCoordinator()
        let auth = try await coordinator.requestAuthorization()

        XCTAssertEqual(auth.userCode, "ABCD-1234")
        XCTAssertEqual(auth.deviceCode, "DEV-CODE-XYZ")
        XCTAssertEqual(auth.verificationURI.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(auth.verificationURIComplete.absoluteString, "https://github.com/login/device?user_code=ABCD-1234")
        XCTAssertEqual(auth.interval, 5)
        XCTAssertEqual(auth.expiresAt.timeIntervalSince1970, 1_700_000_000 + 900, accuracy: 0.5)

        // Form-encoded body should carry client_id and scope.
        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("client_id=Iv1.test"))
        XCTAssertTrue(bodyString.contains("scope=public_repo"))
    }

    func test_requestAuthorizationFallsBackToVerificationURIWhenCompleteMissing() async throws {
        let url = deviceCodeURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, """
            {
              "device_code": "D",
              "user_code": "U",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """)
        }
        let auth = try await makeCoordinator().requestAuthorization()
        XCTAssertEqual(auth.verificationURIComplete.absoluteString, "https://github.com/login/device")
    }

    func test_requestAuthorizationOn500MapsToRelayRejected() async {
        let url = deviceCodeURL()
        MockURLProtocol.handlers[url] = { _ in self.status(url, 500) }
        do {
            _ = try await makeCoordinator().requestAuthorization()
            XCTFail("Expected relayRejected")
        } catch GitTicketsError.relayRejected(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_requestAuthorizationOn429MapsToRateLimited() async {
        let url = deviceCodeURL()
        MockURLProtocol.handlers[url] = { _ in self.status(url, 429, headers: ["Retry-After": "30"]) }
        do {
            _ = try await makeCoordinator().requestAuthorization()
            XCTFail("Expected rateLimited")
        } catch GitTicketsError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - pollForToken — success and pending

    func test_pollReturnsTokenImmediately() async throws {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, """
            {"access_token":"gho_test","token_type":"bearer","scope":"public_repo"}
            """)
        }
        let auth = makeAuth()
        let token = try await makeCoordinator().pollForToken(authorization: auth)
        XCTAssertEqual(token, "gho_test")
    }

    func test_pollReturnsTokenAfterPendingThenSuccess() async throws {
        let url = accessTokenURL()
        let calls = AtomicCounter()
        MockURLProtocol.handlers[url] = { _ in
            let n = calls.increment()
            if n == 1 {
                return self.okJSON(url, #"{"error":"authorization_pending"}"#)
            }
            return self.okJSON(url, #"{"access_token":"gho_after_pending"}"#)
        }
        let token = try await makeCoordinator().pollForToken(authorization: makeAuth())
        XCTAssertEqual(token, "gho_after_pending")
        XCTAssertEqual(calls.value, 2)
    }

    /// `slow_down` must bump our local interval — the next poll uses the new value. We can't
    /// observe the sleep amount directly since we inject a no-op sleep, but we CAN observe that
    /// the loop didn't terminate on the slow_down and proceeded to the next poll.
    func test_pollHandlesSlowDownAndContinues() async throws {
        let url = accessTokenURL()
        let calls = AtomicCounter()
        MockURLProtocol.handlers[url] = { _ in
            let n = calls.increment()
            if n == 1 {
                return self.okJSON(url, #"{"error":"slow_down","interval":10}"#)
            }
            return self.okJSON(url, #"{"access_token":"gho_after_slowdown"}"#)
        }
        let token = try await makeCoordinator().pollForToken(authorization: makeAuth())
        XCTAssertEqual(token, "gho_after_slowdown")
        XCTAssertEqual(calls.value, 2)
    }

    // MARK: - pollForToken — terminal errors

    func test_pollExpiredTokenThrowsDeviceFlowExpired() async {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, #"{"error":"expired_token"}"#)
        }
        do {
            _ = try await makeCoordinator().pollForToken(authorization: makeAuth())
            XCTFail("Expected deviceFlowExpired")
        } catch GitTicketsError.deviceFlowExpired {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_pollAccessDeniedThrowsDeviceFlowDenied() async {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, #"{"error":"access_denied"}"#)
        }
        do {
            _ = try await makeCoordinator().pollForToken(authorization: makeAuth())
            XCTFail("Expected deviceFlowDenied")
        } catch GitTicketsError.deviceFlowDenied {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_pollUnknownErrorThrowsPayloadInvalid() async {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, #"{"error":"incorrect_client_credentials","error_description":"oops"}"#)
        }
        do {
            _ = try await makeCoordinator().pollForToken(authorization: makeAuth())
            XCTFail("Expected payloadInvalid")
        } catch GitTicketsError.payloadInvalid {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_pollEmptyResponseThrowsPayloadInvalid() async {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, #"{}"#)
        }
        do {
            _ = try await makeCoordinator().pollForToken(authorization: makeAuth())
            XCTFail("Expected payloadInvalid")
        } catch GitTicketsError.payloadInvalid {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    /// If the user just closes the browser, GitHub keeps returning `authorization_pending`
    /// forever. The wall-clock cutoff at `expiresAt` is what stops the loop. Drive the clock
    /// past the deadline mid-flow and verify we throw expired.
    func test_pollWallClockExpiryThrowsExpired() async {
        let url = accessTokenURL()
        MockURLProtocol.handlers[url] = { _ in
            self.okJSON(url, #"{"error":"authorization_pending"}"#)
        }
        // Clock starts at t=0 and jumps forward by 1000s on each read — first read seeds
        // expiresAt at 900s, second read (post-sleep, pre-poll) is already past it.
        let clockState = AtomicCounter()
        let clock: @Sendable () -> Date = {
            let n = clockState.increment()
            return Date(timeIntervalSince1970: TimeInterval(n) * 1000)
        }
        let coordinator = DeviceFlowCoordinator(
            clientID: clientID,
            scopes: [.publicRepo],
            http: makeCoordinator().http,
            baseURL: baseURL,
            clock: clock,
            sleep: { _ in }
        )
        let auth = DeviceFlowAuthorization(
            userCode: "X",
            verificationURI: URL(string: "https://example")!,
            verificationURIComplete: URL(string: "https://example")!,
            expiresAt: Date(timeIntervalSince1970: 900),
            interval: 1,
            deviceCode: "D"
        )
        do {
            _ = try await coordinator.pollForToken(authorization: auth)
            XCTFail("Expected deviceFlowExpired")
        } catch GitTicketsError.deviceFlowExpired {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeAuth() -> DeviceFlowAuthorization {
        DeviceFlowAuthorization(
            userCode: "ABCD",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: URL(string: "https://github.com/login/device?user_code=ABCD")!,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_900),
            interval: 1,
            deviceCode: "DEV-CODE"
        )
    }

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

/// Tiny thread-safe counter the test handlers use to make multi-poll handlers ergonomic.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    @discardableResult
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        _value += 1
        return _value
    }
}
