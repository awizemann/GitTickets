import XCTest
@testable import GitTickets

final class HTTPClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handlers.removeAll()
    }

    override func tearDown() {
        MockURLProtocol.handlers.removeAll()
        super.tearDown()
    }

    private func makeClient(maxAttempts: Int = 3) -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let clientConfig = HTTPClient.Configuration(maxAttempts: maxAttempts, baseBackoff: 0.001, maxBackoff: 0.01)
        return HTTPClient(session: session, configuration: clientConfig, userAgent: "Test/1.0")
    }

    private func request(_ urlString: String) -> URLRequest {
        URLRequest(url: URL(string: urlString)!)
    }

    func test_simpleSuccess() async throws {
        let url = URL(string: "https://example.com/ok")!
        MockURLProtocol.handlers[url] = { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["X-Test": "1"])!, Data("hi".utf8))
        }
        let client = makeClient()
        let response = try await client.send(request(url.absoluteString))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, Data("hi".utf8))
        XCTAssertEqual(response.header("X-TEST"), "1")
    }

    func test_userAgentInjected() async throws {
        let url = URL(string: "https://example.com/ua")!
        var capturedUA: String?
        MockURLProtocol.handlers[url] = { request in
            capturedUA = request.value(forHTTPHeaderField: "User-Agent")
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        _ = try await makeClient().send(request(url.absoluteString))
        XCTAssertEqual(capturedUA, "Test/1.0")
    }

    func test_userAgentNotOverriddenWhenCallerProvides() async throws {
        let url = URL(string: "https://example.com/ua2")!
        var capturedUA: String?
        MockURLProtocol.handlers[url] = { request in
            capturedUA = request.value(forHTTPHeaderField: "User-Agent")
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        var req = request(url.absoluteString)
        req.setValue("Custom/9", forHTTPHeaderField: "User-Agent")
        _ = try await makeClient().send(req)
        XCTAssertEqual(capturedUA, "Custom/9")
    }

    func test_retriesOn5xxThenSucceeds() async throws {
        let url = URL(string: "https://example.com/retry")!
        var calls = 0
        MockURLProtocol.handlers[url] = { _ in
            calls += 1
            if calls < 3 {
                return (HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ok".utf8))
        }
        let response = try await makeClient(maxAttempts: 3).send(request(url.absoluteString))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(calls, 3)
    }

    func test_does_not_retry_on_4xx() async throws {
        let url = URL(string: "https://example.com/four")!
        var calls = 0
        MockURLProtocol.handlers[url] = { _ in
            calls += 1
            return (HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil)!, Data())
        }
        let response = try await makeClient(maxAttempts: 3).send(request(url.absoluteString))
        XCTAssertEqual(response.statusCode, 422)
        XCTAssertEqual(calls, 1)
    }

    func test_does_not_retry_429() async throws {
        let url = URL(string: "https://example.com/rate")!
        var calls = 0
        MockURLProtocol.handlers[url] = { _ in
            calls += 1
            return (HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "60"])!, Data())
        }
        let response = try await makeClient(maxAttempts: 3).send(request(url.absoluteString))
        XCTAssertEqual(response.statusCode, 429)
        XCTAssertEqual(response.header("Retry-After"), "60")
        XCTAssertEqual(calls, 1)
    }

    func test_transportErrorRetriesThenThrows() async {
        let url = URL(string: "https://example.com/transport")!
        MockURLProtocol.handlers[url] = { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await makeClient(maxAttempts: 2).send(request(url.absoluteString))
            XCTFail("Expected throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// URLProtocol mock that dispatches per-URL closures.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var handlers: [URL: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handlers[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
