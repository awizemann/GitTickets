import Foundation
import XCTest
@testable import GitTickets

/// Covers ``GitTickets/unreadReplyCount`` and ``GitTickets/checkForReplies()``
/// — the host-facing "you have replies" badge.
///
/// The throttle is the part that matters most: the relay's `/my-issues` shares
/// one per-device budget (10/hour) with `/report`, so a host calling
/// `checkForReplies()` on every activation must not starve the user's next bug
/// report. Every test drives an injected clock so nothing waits on wall time.
final class UnreadRepliesTests: XCTestCase {

    private static let repo = RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public)
    private static let relayURL = URL(string: "https://example.com")!
    private static let secret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))

    private var cache: SubmissionCache!
    private var tempDir: URL!
    private var submitter: MockRepliesSubmitter!
    private var clock: TestClock!

    override func setUpWithError() throws {
        try super.setUpWithError()
        GitTickets._resetConfigurationForTesting()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitTicketsUnreadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = try SubmissionCache(databaseURL: tempDir.appendingPathComponent("submissions.sqlite"))
        submitter = MockRepliesSubmitter(cache: cache)
        clock = TestClock(Date(timeIntervalSince1970: 1_750_000_000))
        GitTickets._setCacheForTesting(cache)
        GitTickets._setSubmitterForTesting(submitter)
        let clock = clock!
        GitTickets._setReplyCheckClockForTesting(now: { clock.now })
    }

    override func tearDownWithError() throws {
        GitTickets._resetConfigurationForTesting()
        cache = nil
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private func configure(myIssuesEnabled: Bool = true) {
        GitTickets.configure(Configuration(
            repo: Self.repo,
            auth: .relay(url: Self.relayURL, sharedSecret: Self.secret),
            myIssues: MyIssuesPolicy(enabled: myIssuesEnabled)
        ))
    }

    @discardableResult
    private func seed(replyCount: Int, readReplyCount: Int = 0) throws -> UUID {
        let id = UUID()
        try cache.upsert(SubmissionRecord(
            submissionID: id,
            issueNumber: Int.random(in: 1...10_000),
            issueURL: URL(string: "https://github.com/alanw/GitTickets/issues/1")!,
            title: "Report",
            kind: .bug,
            body: "Body",
            deviceID: "device",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            submittedAt: Date(timeIntervalSince1970: 1_750_000_000),
            replyCount: replyCount,
            readReplyCount: readReplyCount
        ))
        return id
    }

    private let interval = ReplyCheckThrottle.defaultMinimumInterval

    // MARK: unreadReplyCount

    func test_unreadReplyCount_sumsUnreadAcrossCachedSubmissions() throws {
        configure()
        XCTAssertEqual(GitTickets.unreadReplyCount, 0, "empty cache: COALESCE turns SUM's NULL into 0")
        try seed(replyCount: 3, readReplyCount: 1)   // 2 unread
        try seed(replyCount: 4, readReplyCount: 4)   // 0 unread
        try seed(replyCount: 1)                      // 1 unread
        try seed(replyCount: 1, readReplyCount: 3)   // a deleted comment: clamps to 0, not -2
        XCTAssertEqual(GitTickets.unreadReplyCount, 3)
        XCTAssertEqual(
            GitTickets.unreadReplyCount,
            GitTickets.cachedSubmissions().reduce(0) { $0 + $1.unreadReplyCount },
            "the SQL sum must agree with the per-row projection"
        )
        XCTAssertEqual(submitter.fetchCount, 0, "unreadReplyCount must never hit the network")
    }

    func test_unreadReplyCount_isZeroWhenUnconfigured() throws {
        try seed(replyCount: 5)
        XCTAssertEqual(GitTickets.unreadReplyCount, 0)
    }

    func test_unreadReplyCount_dropsAfterMarkingRead() throws {
        configure()
        let id = try seed(replyCount: 2)
        XCTAssertEqual(GitTickets.unreadReplyCount, 2)
        GitTickets.markRepliesRead(submissionID: id, count: 2)
        XCTAssertEqual(GitTickets.unreadReplyCount, 0)
    }

    // MARK: checkForReplies — throttle

    func test_checkForReplies_hitsNetworkThenThrottlesThenHitsAgainAfterInterval() async throws {
        configure()
        let id = try seed(replyCount: 0)

        submitter.setReplyCount(1, for: id)
        let first = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
        XCTAssertEqual(first, 1)

        // Just inside the interval: cached answer, no request — even though
        // the backend now has more replies.
        submitter.setReplyCount(2, for: id)
        clock.advance(interval - 1)
        let throttled = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
        XCTAssertEqual(throttled, 1, "throttled call returns the cached total")

        // Interval elapsed: hits the network again.
        clock.advance(1)
        let second = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
        XCTAssertEqual(second, 2)
    }

    func test_checkForReplies_returnsUpdatedTotalAndKeepsReadCounts() async throws {
        configure()
        let a = try seed(replyCount: 2, readReplyCount: 2)
        let b = try seed(replyCount: 1, readReplyCount: 0)
        XCTAssertEqual(GitTickets.unreadReplyCount, 1)

        submitter.setReplyCount(5, for: a)  // 3 new on an already-read issue
        submitter.setReplyCount(1, for: b)  // unchanged
        let total = await GitTickets.checkForReplies()

        XCTAssertEqual(total, 4)
        XCTAssertEqual(GitTickets.unreadReplyCount, 4, "the refresh is persisted to the cache")
        XCTAssertEqual(Set(submitter.requestedIDs), [a, b])
    }

    // MARK: checkForReplies — no network

    func test_checkForReplies_noNetworkWhenUnconfigured() async throws {
        try seed(replyCount: 2)
        let total = await GitTickets.checkForReplies()
        XCTAssertEqual(total, 0)
        XCTAssertEqual(submitter.fetchCount, 0)
        XCTAssertNil(try cache.metaDate(forKey: ReplyCheckThrottle.metaKey))

        // The unconfigured call must not have spent the throttle slot (a
        // missing guard would claim it and fail with .notConfigured).
        configure()
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    func test_checkForReplies_noNetworkWhenMyIssuesDisabled() async throws {
        configure(myIssuesEnabled: false)
        try seed(replyCount: 2, readReplyCount: 1)
        let total = await GitTickets.checkForReplies()
        XCTAssertEqual(total, 1, "returns the cached total")
        XCTAssertEqual(submitter.fetchCount, 0)
    }

    func test_checkForReplies_noNetworkWhenNothingFiled() async {
        configure()
        let total = await GitTickets.checkForReplies()
        XCTAssertEqual(total, 0)
        XCTAssertEqual(submitter.fetchCount, 0)
    }

    /// An empty-cache check must not spend the throttle slot, or a user who
    /// files their first report would wait out the interval for replies.
    func test_checkForReplies_nothingFiledDoesNotConsumeThrottle() async throws {
        configure()
        await GitTickets.checkForReplies()
        try seed(replyCount: 1)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    // MARK: checkForReplies — errors

    func test_checkForReplies_errorFallsBackToCachedTotal() async throws {
        configure()
        try seed(replyCount: 3, readReplyCount: 1)
        submitter.setError(GitTicketsError.relayRejected(statusCode: 500, message: nil))
        let total = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
        XCTAssertEqual(total, 2)
    }

    func test_checkForReplies_rateLimitedCountsAgainstThrottle() async throws {
        configure()
        let id = try seed(replyCount: 0)
        submitter.setError(GitTicketsError.rateLimited(retryAfter: 60))
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)

        submitter.setError(nil)
        submitter.setReplyCount(1, for: id)
        clock.advance(60)
        let throttled = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1, "a 429 must not be retried inside the interval")
        XCTAssertEqual(throttled, 0)

        clock.advance(interval)
        let recovered = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
        XCTAssertEqual(recovered, 1)
    }

    /// Relay rejections reached the relay (and spent budget), so they hold
    /// off the next lookup just like a 429.
    func test_checkForReplies_relayRejectionCountsAgainstThrottle() async throws {
        configure()
        try seed(replyCount: 0)
        submitter.setError(GitTicketsError.relayRejected(statusCode: 503, message: nil))
        await GitTickets.checkForReplies()
        submitter.setError(nil)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    /// A pre-connection failure never reached the relay, so it spent no
    /// budget — the next call (e.g. once the launch-time network settles)
    /// retries.
    func test_checkForReplies_offlineDoesNotCountAgainstThrottle() async throws {
        configure()
        let id = try seed(replyCount: 0)
        submitter.setError(GitTicketsError.relayUnreachable(underlying: URLError(.notConnectedToInternet)))
        let offline = await GitTickets.checkForReplies()
        XCTAssertEqual(offline, 0)

        submitter.setError(nil)
        submitter.setReplyCount(2, for: id)
        let online = await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
        XCTAssertEqual(online, 2)

        // The successful retry does count.
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
    }

    /// A timeout usually means the relay received — and counted — the
    /// request, so it holds off the next lookup.
    func test_checkForReplies_timeoutCountsAgainstThrottle() async throws {
        configure()
        try seed(replyCount: 0)
        submitter.setError(GitTicketsError.relayUnreachable(underlying: URLError(.timedOut)))
        await GitTickets.checkForReplies()
        submitter.setError(nil)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    /// Handing the slot back also clears the persisted window, so a cold
    /// launch after an offline check retries too.
    func test_checkForReplies_offlineFailureClearsPersistedWindow() async throws {
        configure()
        try seed(replyCount: 0)
        submitter.setError(GitTicketsError.relayUnreachable(underlying: URLError(.cannotFindHost)))
        await GitTickets.checkForReplies()
        XCTAssertNil(try cache.metaDate(forKey: ReplyCheckThrottle.metaKey))

        try simulateColdLaunch()
        submitter.setError(nil)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
    }

    // MARK: checkForReplies — persistence

    /// iOS relaunches apps constantly; an in-memory window alone would let
    /// every cold launch hit the relay.
    func test_checkForReplies_throttleSurvivesColdLaunch() async throws {
        configure()
        try seed(replyCount: 0)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
        XCTAssertEqual(try cache.metaDate(forKey: ReplyCheckThrottle.metaKey), clock.now)

        try simulateColdLaunch()
        clock.advance(60)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1, "a fresh process must still honour the window")

        clock.advance(interval)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
    }

    /// A failed (non-counting) check must not wipe a newer window stamped
    /// by a successful My Reports refresh that finished while it was in
    /// flight. Driven step by step on the throttle so the interleaving is
    /// fixed.
    func test_failedCheckDoesNotClearNewerWindowFromConcurrentRefresh() throws {
        let throttle = ReplyCheckThrottle()
        let clock = clock!
        throttle.setClock(now: { clock.now }, minimumInterval: interval)

        // 1. A reply check claims the slot at T1.
        var token = -1
        let check = throttle.claim(cache: cache) { t in token = t; return Task { 0 } }
        XCTAssertNotNil(check)
        let claimedAt = clock.now

        // 2. Meanwhile My Reports refreshes successfully at T2.
        clock.advance(30)
        throttle.recordCheck(cache: cache)
        let refreshedAt = clock.now

        // 3. The reply check then fails offline and hands its slot back.
        throttle.finish(token, countsAgainstThrottle: false, cache: cache)

        XCTAssertEqual(try cache.metaDate(forKey: ReplyCheckThrottle.metaKey), refreshedAt)
        XCTAssertNotEqual(refreshedAt, claimedAt)
        clock.advance(60)
        XCTAssertNil(throttle.claim(cache: cache) { _ in Task { 0 } }, "the refresh's window must survive")
    }

    /// Without the race, a failed check does clear its own window.
    func test_failedCheckClearsItsOwnWindow() throws {
        let throttle = ReplyCheckThrottle()
        let clock = clock!
        throttle.setClock(now: { clock.now }, minimumInterval: interval)
        var token = -1
        _ = throttle.claim(cache: cache) { t in token = t; return Task { 0 } }
        throttle.finish(token, countsAgainstThrottle: false, cache: cache)
        XCTAssertNil(try cache.metaDate(forKey: ReplyCheckThrottle.metaKey))
        XCTAssertNotNil(throttle.claim(cache: cache) { _ in Task { 0 } })
    }

    /// If the `meta` table is unusable (missing and can't be created), the
    /// throttle still works from memory for the rest of the run.
    func test_throttleFallsBackToMemoryWithoutMetaTable() throws {
        let path = tempDir.appendingPathComponent("submissions.sqlite").path
        // Hold a write lock from a second connection so the meta table
        // can't be recreated, then drop it out from under the cache.
        try sqliteExec(path, "DROP TABLE meta")
        let blocker = try SQLiteHandle(path: path)
        try blocker.exec("BEGIN IMMEDIATE")
        defer { try? blocker.exec("ROLLBACK") }
        let reopened = try SubmissionCache(databaseURL: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try reopened.metaDate(forKey: ReplyCheckThrottle.metaKey))

        let throttle = ReplyCheckThrottle()
        let clock = clock!
        throttle.setClock(now: { clock.now }, minimumInterval: interval)
        var token = -1
        XCTAssertNotNil(throttle.claim(cache: reopened) { t in token = t; return Task { 0 } })
        throttle.finish(token, countsAgainstThrottle: true, cache: reopened)
        clock.advance(60)
        XCTAssertNil(throttle.claim(cache: reopened) { _ in Task { 0 } }, "in-memory window applies")
    }

    /// A wall clock that moves backwards must not freeze the throttle until
    /// it catches up.
    func test_checkForReplies_clockMovedBackwardsIsAllowed() async throws {
        configure()
        try seed(replyCount: 0)
        await GitTickets.checkForReplies()
        clock.advance(-3_600)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 2)
    }

    // MARK: checkForReplies — interaction with My Reports

    /// My Reports' own refresh spends the same budget, so a check right
    /// after it is skipped.
    func test_refreshMyIssuesStartsTheWindow() async throws {
        configure()
        try seed(replyCount: 0)
        _ = try await GitTickets.refreshMyIssuesDetailed()
        XCTAssertEqual(submitter.fetchCount, 1)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    /// A badge check must not let HTTPClient multiply one 5xx into three
    /// counted relay requests; My Reports' refresh keeps its retries.
    func test_checkForRepliesLimitsAttemptsToOne() async throws {
        configure()
        try seed(replyCount: 0)
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.attemptLimits, [1])

        clock.advance(interval)
        _ = try await GitTickets.refreshMyIssuesDetailed()
        XCTAssertEqual(submitter.attemptLimits, [1, nil])
    }

    // MARK: checkForReplies — concurrency

    func test_checkForReplies_concurrentCallsShareOneRequest() async throws {
        configure()
        let id = try seed(replyCount: 0)
        submitter.setReplyCount(3, for: id)
        submitter.setDelay(.milliseconds(200))

        let results = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { await GitTickets.checkForReplies() }
            }
            var all: [Int] = []
            for await value in group { all.append(value) }
            return all
        }

        XCTAssertEqual(submitter.fetchCount, 1)
        XCTAssertEqual(results.count, 8)
        // Callers that arrived mid-flight join the request, so they see the
        // refreshed total rather than the stale cache.
        XCTAssertEqual(results, Array(repeating: 3, count: 8))
    }

    // MARK: configure

    /// Re-configuring does not reset the throttle: the budget it protects is
    /// per device, not per configuration, and hosts may re-call configure.
    func test_reconfigureDoesNotResetThrottle() async throws {
        configure()
        try seed(replyCount: 0)
        await GitTickets.checkForReplies()
        configure()
        await GitTickets.checkForReplies()
        XCTAssertEqual(submitter.fetchCount, 1)
    }

    // MARK: Error classification

    func test_countsAgainstThrottleClassification() {
        func unreachable(_ code: URLError.Code) -> GitTicketsError {
            .relayUnreachable(underlying: URLError(code))
        }
        // Counted: reached (or probably reached) the relay.
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.rateLimited(retryAfter: nil)))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.relayRejected(statusCode: 500, message: nil)))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.signatureMismatch))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(unreachable(.timedOut)))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(unreachable(.networkConnectionLost)))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(unreachable(.cancelled)))
        XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.relayUnreachable(underlying: CocoaError(.fileNoSuchFile))))
        // Not counted: no request was sent.
        for code: URLError.Code in [
            .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed,
        ] {
            XCTAssertFalse(ReplyCheckThrottle.countsAgainstThrottle(unreachable(code)), "\(code)")
        }
        // No Device Flow token: thrown before any request; signing in fixes it.
        XCTAssertFalse(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.deviceFlowNotAuthorized))
    }

    /// The classification depends on RelayClient keeping the raw URLError as
    /// `underlying` — pin that through the real client and HTTPClient.
    func test_relayClientPreservesURLErrorCode() async throws {
        let base = URL(string: "https://relay-timeout.example.com")!
        let endpoint = base.appendingPathComponent("my-issues")
        MockURLProtocol.handlers[endpoint] = { _ in throw URLError(.timedOut) }
        defer { MockURLProtocol.handlers[endpoint] = nil }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let http = HTTPClient(
            session: URLSession(configuration: sessionConfig),
            configuration: .init(maxAttempts: 3, baseBackoff: 0.001, maxBackoff: 0.01),
            userAgent: "Test/1.0"
        )
        let client = RelayClient(baseURL: base, secret: Self.secret, http: http)
        do {
            _ = try await client.fetchMyIssues(MyIssuesRequest(submissionIDs: [UUID().uuidString], deviceID: "d"))
            XCTFail("Expected relayUnreachable")
        } catch GitTicketsError.relayUnreachable(let underlying) {
            XCTAssertEqual((underlying as? URLError)?.code, .timedOut)
            XCTAssertTrue(ReplyCheckThrottle.countsAgainstThrottle(GitTicketsError.relayUnreachable(underlying: underlying)))
        }
    }

    // MARK: Cold launch

    /// Drops all in-process state, then reopens the same SQLite file the way
    /// a relaunched app would.
    private func simulateColdLaunch() throws {
        GitTickets._resetConfigurationForTesting()
        cache = try SubmissionCache(databaseURL: tempDir.appendingPathComponent("submissions.sqlite"))
        submitter = MockRepliesSubmitter(cache: cache, carryingCountFrom: submitter)
        GitTickets._setCacheForTesting(cache)
        GitTickets._setSubmitterForTesting(submitter)
        let clock = clock!
        GitTickets._setReplyCheckClockForTesting(now: { clock.now })
        configure()
    }
}

// MARK: - Test doubles

/// Mutable clock shared with the throttle.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// Stands in for ``RelaySubmitter``'s `/my-issues` lookup: counts calls and
/// writes reply counts into the cache the way the real submitter does,
/// leaving `read_reply_count` alone.
private final class MockRepliesSubmitter: IssueSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private let cache: SubmissionCache
    private var replyCounts: [UUID: Int] = [:]
    private var error: (any Error)?
    private var delay: Duration?
    private var _fetchCount = 0
    private var _requestedIDs: [UUID] = []
    private var _attemptLimits: [Int?] = []

    init(cache: SubmissionCache) { self.cache = cache }

    /// A post-"relaunch" submitter that keeps counting from `previous`, so
    /// assertions span the simulated cold launch.
    init(cache: SubmissionCache, carryingCountFrom previous: MockRepliesSubmitter) {
        self.cache = cache
        self._fetchCount = previous.fetchCount
    }

    var fetchCount: Int { lock.withLock { _fetchCount } }
    var requestedIDs: [UUID] { lock.withLock { _requestedIDs } }
    /// The ``HTTPClient/attemptLimit`` in effect for each fetch.
    var attemptLimits: [Int?] { lock.withLock { _attemptLimits } }

    func setReplyCount(_ count: Int, for id: UUID) { lock.withLock { replyCounts[id] = count } }
    func setError(_ error: (any Error)?) { lock.withLock { self.error = error } }
    func setDelay(_ delay: Duration?) { lock.withLock { self.delay = delay } }

    func submit(_ report: Report) async throws -> SubmittedIssue {
        XCTFail("submit is not under test")
        throw GitTicketsError.notConfigured
    }

    func fetchMyIssues(submissionIDs: [UUID], deviceID: String) async throws -> [SubmittedIssue] {
        let (delay, error, counts) = lock.withLock {
            _fetchCount += 1
            _requestedIDs = submissionIDs
            _attemptLimits.append(HTTPClient.attemptLimit)
            return (self.delay, self.error, replyCounts)
        }
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        return try submissionIDs.compactMap { id in
            guard var record = try cache.record(submissionID: id) else { return nil }
            if let count = counts[id] { record.replyCount = count }
            try cache.upsert(record)
            return record.asSubmittedIssue
        }
    }
}
