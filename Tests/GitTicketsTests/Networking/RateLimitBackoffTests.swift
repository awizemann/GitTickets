import XCTest
@testable import GitTickets

final class RateLimitBackoffTests: XCTestCase {

    func test_parseDeltaSeconds() {
        XCTAssertEqual(RateLimitBackoff.parseRetryAfter("120"), 120)
        XCTAssertEqual(RateLimitBackoff.parseRetryAfter("0"), 0)
    }

    func test_parseDeltaSecondsToleratesWhitespace() {
        XCTAssertEqual(RateLimitBackoff.parseRetryAfter("  60  "), 60)
    }

    func test_parseHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        let future = now.addingTimeInterval(300)
        let formatted = formatter.string(from: future)
        let seconds = RateLimitBackoff.parseRetryAfter(formatted, now: now)
        XCTAssertEqual(seconds ?? 0, 300, accuracy: 1)
    }

    func test_parseRejectsNonsense() {
        XCTAssertNil(RateLimitBackoff.parseRetryAfter("nope"))
        XCTAssertNil(RateLimitBackoff.parseRetryAfter(""))
    }

    func test_exponentialDelayGrowsAndCaps() {
        // Use jitter: false to assert exact growth shape.
        let zero = RateLimitBackoff.exponentialDelay(attempt: 0, base: 0.5, maxDelay: 30, jitter: false)
        let one = RateLimitBackoff.exponentialDelay(attempt: 1, base: 0.5, maxDelay: 30, jitter: false)
        let big = RateLimitBackoff.exponentialDelay(attempt: 10, base: 0.5, maxDelay: 30, jitter: false)
        XCTAssertEqual(zero, 0.5)
        XCTAssertEqual(one, 1.0)
        XCTAssertEqual(big, 30)
    }

    func test_exponentialDelayJitterStaysInBand() {
        // With jitter, the result is scaled by [0.5, 1.5). For 200 samples
        // at attempt 2 (base*4 = 2.0), every value must fall in [1.0, 3.0).
        for _ in 0..<200 {
            let delay = RateLimitBackoff.exponentialDelay(attempt: 2, base: 0.5, maxDelay: 30, jitter: true)
            XCTAssertGreaterThanOrEqual(delay, 1.0)
            XCTAssertLessThan(delay, 3.0)
        }
    }

    func test_exponentialDelayTreatsNegativeAttemptAsBase() {
        XCTAssertEqual(RateLimitBackoff.exponentialDelay(attempt: -1, base: 0.25, jitter: false), 0.25)
    }
}
