import XCTest
@testable import GitTickets

final class SubmissionCacheTests: XCTestCase {

    private var cache: SubmissionCache!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitTicketsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("submissions.sqlite")
        cache = try SubmissionCache(databaseURL: dbURL)
    }

    override func tearDownWithError() throws {
        cache = nil
        if let dbURL {
            let parent = dbURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: parent)
        }
        try super.tearDownWithError()
    }

    private func makeRecord(
        submissionID: UUID = UUID(),
        issueNumber: Int = 42,
        title: String = "Test",
        submittedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        replyCount: Int = 0,
        readReplyCount: Int = 0,
        latestReplyAt: Date? = nil
    ) -> SubmissionRecord {
        SubmissionRecord(
            submissionID: submissionID,
            issueNumber: issueNumber,
            issueURL: URL(string: "https://github.com/x/y/issues/\(issueNumber)")!,
            title: title,
            kind: .bug,
            body: "Body for \(submissionID.uuidString)",
            deviceID: "device-1",
            createdAt: submittedAt.addingTimeInterval(0.5),
            submittedAt: submittedAt,
            latestReplyAt: latestReplyAt,
            replyCount: replyCount,
            readReplyCount: readReplyCount
        )
    }

    // MARK: - Round trip

    func test_upsertThenFetch() throws {
        let record = makeRecord()
        try cache.upsert(record)
        let fetched = try cache.record(submissionID: record.submissionID)
        XCTAssertEqual(fetched, record)
    }

    func test_recordMissingReturnsNil() throws {
        XCTAssertNil(try cache.record(submissionID: UUID()))
    }

    // MARK: - Ordering

    func test_allRecordsOrderedBySubmittedAtDescending() throws {
        let older = makeRecord(
            issueNumber: 1, title: "older",
            submittedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeRecord(
            issueNumber: 2, title: "newer",
            submittedAt: Date(timeIntervalSince1970: 200)
        )
        try cache.upsert(older)
        try cache.upsert(newer)
        let all = try cache.allRecords()
        XCTAssertEqual(all.map(\.title), ["newer", "older"])
    }

    // MARK: - Upsert semantics

    func test_upsertReplacesExisting() throws {
        let id = UUID()
        try cache.upsert(makeRecord(submissionID: id, title: "v1"))
        try cache.upsert(makeRecord(submissionID: id, title: "v2"))
        let all = try cache.allRecords()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "v2")
    }

    // MARK: - Reply tracking

    func test_markRepliesReadUpdatesCount() throws {
        let record = makeRecord(replyCount: 5, readReplyCount: 0)
        try cache.upsert(record)
        try cache.markRepliesRead(submissionID: record.submissionID, count: 3)
        let fetched = try XCTUnwrap(try cache.record(submissionID: record.submissionID))
        XCTAssertEqual(fetched.readReplyCount, 3)
        XCTAssertEqual(fetched.unreadReplyCount, 2)
    }

    func test_latestReplyAtRoundTrips() throws {
        let replyTime = Date(timeIntervalSince1970: 1_700_000_500)
        let record = makeRecord(replyCount: 1, latestReplyAt: replyTime)
        try cache.upsert(record)
        let fetched = try XCTUnwrap(try cache.record(submissionID: record.submissionID))
        let actual = try XCTUnwrap(fetched.latestReplyAt?.timeIntervalSince1970)
        XCTAssertEqual(actual, replyTime.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_nullLatestReplyAtRoundTrips() throws {
        let record = makeRecord(latestReplyAt: nil)
        try cache.upsert(record)
        let fetched = try XCTUnwrap(try cache.record(submissionID: record.submissionID))
        XCTAssertNil(fetched.latestReplyAt)
    }

    // MARK: - Delete

    func test_deleteRemovesOne() throws {
        let a = makeRecord(issueNumber: 1)
        let b = makeRecord(issueNumber: 2)
        try cache.upsert(a)
        try cache.upsert(b)
        try cache.delete(submissionID: a.submissionID)
        let all = try cache.allRecords()
        XCTAssertEqual(all.map(\.issueNumber), [2])
    }

    func test_deleteAllClears() throws {
        try cache.upsert(makeRecord(issueNumber: 1))
        try cache.upsert(makeRecord(issueNumber: 2))
        try cache.deleteAll()
        XCTAssertTrue(try cache.allRecords().isEmpty)
    }

    // MARK: - Public projection

    func test_asSubmittedIssueProjectsCorrectly() throws {
        let record = makeRecord(replyCount: 4, readReplyCount: 1)
        try cache.upsert(record)
        let fetched = try XCTUnwrap(try cache.record(submissionID: record.submissionID))
        let projection = fetched.asSubmittedIssue
        XCTAssertEqual(projection.id, record.submissionID)
        XCTAssertEqual(projection.issueNumber, record.issueNumber)
        XCTAssertEqual(projection.unreadReplyCount, 3)
    }

    // MARK: - Persistence across instances

    func test_dataSurvivesReopen() throws {
        let record = makeRecord()
        try cache.upsert(record)
        cache = nil

        let reopened = try SubmissionCache(databaseURL: dbURL)
        let fetched = try reopened.record(submissionID: record.submissionID)
        XCTAssertEqual(fetched, record)
    }

    // MARK: - Upgrade from v2.5.0

    /// The exact v2.5.0 schema (from `git show v2.5.0:…/SubmissionCache.swift`),
    /// with one row: 3 replies, 1 read.
    private func makeV250Database() throws -> (url: URL, id: UUID) {
        let url = dbURL.deletingLastPathComponent().appendingPathComponent("v250.sqlite")
        let id = UUID()
        let handle = try SQLiteHandle(path: url.path)
        try handle.exec("""
            CREATE TABLE IF NOT EXISTS submissions (
                submission_id TEXT PRIMARY KEY,
                issue_number INTEGER NOT NULL,
                issue_url TEXT NOT NULL,
                title TEXT NOT NULL,
                kind TEXT NOT NULL,
                body TEXT NOT NULL,
                device_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                submitted_at REAL NOT NULL,
                latest_reply_at REAL,
                reply_count INTEGER NOT NULL DEFAULT 0,
                read_reply_count INTEGER NOT NULL DEFAULT 0
            );
            """)
        try handle.exec("""
            CREATE INDEX IF NOT EXISTS idx_submissions_submitted_at
                ON submissions(submitted_at DESC);
            """)
        try handle.exec("""
            INSERT INTO submissions VALUES (
                '\(id.uuidString)', 7, 'https://github.com/alanw/GitTickets/issues/7',
                'Old report', 'bug', 'Old body', 'device', 1750000000, 1750000000,
                NULL, 3, 1
            );
            """)
        return (url, id)
    }

    /// A v2.5.0 database opens, keeps its rows, and gains a working `meta`
    /// table.
    func test_v250DatabaseUpgradesInPlace() throws {
        let (url, id) = try makeV250Database()
        let upgraded = try SubmissionCache(databaseURL: url)

        let record = try XCTUnwrap(upgraded.record(submissionID: id))
        XCTAssertEqual(record.issueNumber, 7)
        XCTAssertEqual(record.body, "Old body")
        XCTAssertEqual(try upgraded.recordCount(), 1)
        XCTAssertEqual(try upgraded.unreadReplyTotal(), 2)

        XCTAssertNil(try upgraded.metaDate(forKey: "k"))
        let stamp = Date(timeIntervalSince1970: 1_750_000_123.5)
        try upgraded.setMetaDate(stamp, forKey: "k")
        XCTAssertEqual(try upgraded.metaDate(forKey: "k"), stamp)
    }

    /// On the first launch after upgrading, creating `meta` is the first
    /// write. If it fails (here: another connection holds the write lock;
    /// in the field, a full disk), the cache must still open with its data
    /// — v2.5.0 would have — and `meta` comes up once writes work again.
    func test_v250DatabaseOpensWhenMetaTableCannotBeCreated() throws {
        let (url, id) = try makeV250Database()
        let blocker = try SQLiteHandle(path: url.path)
        try blocker.exec("BEGIN IMMEDIATE")

        let upgraded = try SubmissionCache(databaseURL: url)
        XCTAssertNotNil(try upgraded.record(submissionID: id))
        XCTAssertEqual(try upgraded.unreadReplyTotal(), 2)
        XCTAssertThrowsError(try upgraded.metaDate(forKey: "k"), "no meta table yet; callers fall back")

        try blocker.exec("ROLLBACK")
        let stamp = Date(timeIntervalSince1970: 1_750_000_456)
        try upgraded.setMetaDate(stamp, forKey: "k")
        XCTAssertEqual(try upgraded.metaDate(forKey: "k"), stamp)
    }

    func test_clearMetaDateOnlyClearsMatchingValue() throws {
        let older = Date(timeIntervalSince1970: 1_750_000_000)
        let newer = Date(timeIntervalSince1970: 1_750_000_030)
        try cache.setMetaDate(newer, forKey: "k")
        try cache.clearMetaDate(forKey: "k", ifEqualTo: older)
        XCTAssertEqual(try cache.metaDate(forKey: "k"), newer)
        try cache.clearMetaDate(forKey: "k", ifEqualTo: newer)
        XCTAssertNil(try cache.metaDate(forKey: "k"))
    }
}
