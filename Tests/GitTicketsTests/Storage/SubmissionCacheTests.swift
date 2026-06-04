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
}
