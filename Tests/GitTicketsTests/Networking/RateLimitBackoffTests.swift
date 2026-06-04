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
        let zero = RateLimitBackoff.exponentialDelay(attempt: 0, base: 0.5, maxDelay: 30)
        let one = RateLimitBackoff.exponentialDelay(attempt: 1, base: 0.5, maxDelay: 30)
        let big = RateLimitBackoff.exponentialDelay(attempt: 10, base: 0.5, maxDelay: 30)
        XCTAssertEqual(zero, 0.5)
        XCTAssertEqual(one, 1.0)
        XCTAssertEqual(big, 30)
    }

    func test_exponentialDelayTreatsNegativeAttemptAsBase() {
        XCTAssertEqual(RateLimitBackoff.exponentialDelay(attempt: -1, base: 0.25), 0.25)
    }
}
