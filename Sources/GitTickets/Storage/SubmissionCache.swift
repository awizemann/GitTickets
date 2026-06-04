import Foundation
import SQLite3

/// SQLite-backed cache of submitted issues, used by the Phase 2
/// "My Issues" view for offline browsing and read-state tracking.
///
/// Schema is migrated lazily on first connection. All operations run on an
/// internal serial queue; the type is `@unchecked Sendable` because it owns
/// its concurrency.
///
/// Default file lives under:
/// - macOS: `~/Library/Application Support/<bundleID>/GitTickets/submissions.sqlite`
/// - iOS: `<sandboxed Application Support>/GitTickets/submissions.sqlite`
///
/// Tests pass an explicit `databaseURL` pointing at a temp file.
final class SubmissionCache: @unchecked Sendable {

    enum CacheError: Error {
        case openFailed(Int32, String?)
        case prepareFailed(Int32, String?)
        case stepFailed(Int32, String?)
    }

    private let queue = DispatchQueue(label: "com.gittickets.submission-cache")
    private var db: OpaquePointer?

    // MARK: - Init

    /// Opens the database at the given URL, creating parent directories and
    /// running the schema migration as needed.
    init(databaseURL: URL) throws {
        try createParentDirectory(for: databaseURL)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) }
            sqlite3_close(handle)
            throw CacheError.openFailed(status, message)
        }
        self.db = handle

        try queue.sync { try runMigrations() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Builds the production database URL under Application Support.
    static func defaultDatabaseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "GitTickets"
        let dir = support.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("GitTickets", isDirectory: true)
        return dir.appendingPathComponent("submissions.sqlite", isDirectory: false)
    }

    private func createParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        let createTable = """
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
            """
        let createIndex = """
            CREATE INDEX IF NOT EXISTS idx_submissions_submitted_at
                ON submissions(submitted_at DESC);
            """
        try execute(createTable)
        try execute(createIndex)
    }

    // MARK: - Public API

    /// Inserts or updates a record keyed by `submission_id`.
    func upsert(_ record: SubmissionRecord) throws {
        try queue.sync { try _upsert(record) }
    }

    /// Returns the record for the given submission, or `nil` when absent.
    func record(submissionID: UUID) throws -> SubmissionRecord? {
        try queue.sync { try _record(submissionID: submissionID) }
    }

    /// Returns all records ordered by `submitted_at` descending (newest first).
    func allRecords() throws -> [SubmissionRecord] {
        try queue.sync { try _allRecords() }
    }

    /// Sets `read_reply_count` to the given count for the submission.
    /// Used when the user opens the issue detail view and acknowledges replies.
    func markRepliesRead(submissionID: UUID, count: Int) throws {
        try queue.sync {
            try _execute(
                "UPDATE submissions SET read_reply_count = ? WHERE submission_id = ?",
                bindings: [.int(Int64(count)), .text(submissionID.uuidString)]
            )
        }
    }

    /// Removes a single record. Mainly used in tests; production has no
    /// "forget submission" flow in v1.
    func delete(submissionID: UUID) throws {
        try queue.sync {
            try _execute(
                "DELETE FROM submissions WHERE submission_id = ?",
                bindings: [.text(submissionID.uuidString)]
            )
        }
    }

    /// Removes every record. Tests only.
    func deleteAll() throws {
        try queue.sync { try _execute("DELETE FROM submissions") }
    }

    // MARK: - Internal queue-bound implementations

    private func _upsert(_ record: SubmissionRecord) throws {
        let sql = """
            INSERT INTO submissions (
                submission_id, issue_number, issue_url, title, kind, body,
                device_id, created_at, submitted_at,
                latest_reply_at, reply_count, read_reply_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(submission_id) DO UPDATE SET
                issue_number = excluded.issue_number,
                issue_url = excluded.issue_url,
                title = excluded.title,
                kind = excluded.kind,
                body = excluded.body,
                device_id = excluded.device_id,
                created_at = excluded.created_at,
                submitted_at = excluded.submitted_at,
                latest_reply_at = excluded.latest_reply_at,
                reply_count = excluded.reply_count,
                read_reply_count = excluded.read_reply_count;
            """
        let bindings: [Binding] = [
            .text(record.submissionID.uuidString),
            .int(Int64(record.issueNumber)),
            .text(record.issueURL.absoluteString),
            .text(record.title),
            .text(record.kind.rawValue),
            .text(record.body),
            .text(record.deviceID),
            .double(record.createdAt.timeIntervalSince1970),
            .double(record.submittedAt.timeIntervalSince1970),
            record.latestReplyAt.map { Binding.double($0.timeIntervalSince1970) } ?? .null,
            .int(Int64(record.replyCount)),
            .int(Int64(record.readReplyCount)),
        ]
        try _execute(sql, bindings: bindings)
    }

    private func _record(submissionID: UUID) throws -> SubmissionRecord? {
        let sql = "SELECT \(selectColumns) FROM submissions WHERE submission_id = ? LIMIT 1"
        return try _firstRecord(sql: sql, bindings: [.text(submissionID.uuidString)])
    }

    private func _allRecords() throws -> [SubmissionRecord] {
        let sql = "SELECT \(selectColumns) FROM submissions ORDER BY submitted_at DESC"
        return try _allRecords(sql: sql, bindings: [])
    }

    private let selectColumns = """
        submission_id, issue_number, issue_url, title, kind, body, device_id,
        created_at, submitted_at, latest_reply_at, reply_count, read_reply_count
        """

    private func _firstRecord(sql: String, bindings: [Binding]) throws -> SubmissionRecord? {
        let results = try _allRecords(sql: sql, bindings: bindings)
        return results.first
    }

    private func _allRecords(sql: String, bindings: [Binding]) throws -> [SubmissionRecord] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CacheError.prepareFailed(prepareStatus, message)
        }
        defer { sqlite3_finalize(statement) }

        try Self.bind(bindings, to: statement)

        var results: [SubmissionRecord] = []
        while true {
            let stepStatus = sqlite3_step(statement)
            switch stepStatus {
            case SQLITE_ROW:
                if let record = Self.readRecord(from: statement) {
                    results.append(record)
                }
            case SQLITE_DONE:
                return results
            default:
                let message = String(cString: sqlite3_errmsg(db))
                throw CacheError.stepFailed(stepStatus, message)
            }
        }
    }

    private func _execute(_ sql: String, bindings: [Binding] = []) throws {
        guard let db else { return }
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CacheError.prepareFailed(prepareStatus, message)
        }
        defer { sqlite3_finalize(statement) }

        try Self.bind(bindings, to: statement)

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE || stepStatus == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CacheError.stepFailed(stepStatus, message)
        }
    }

    private func execute(_ sql: String) throws {
        try _execute(sql)
    }

    // MARK: - SQLite bind / read helpers

    private enum Binding {
        case text(String)
        case int(Int64)
        case double(Double)
        case null
    }

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (zeroBasedIndex, binding) in bindings.enumerated() {
            let index = Int32(zeroBasedIndex + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .int(let value):
                sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                sqlite3_bind_double(statement, index, value)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
    }

    private static func readRecord(from statement: OpaquePointer) -> SubmissionRecord? {
        guard
            let submissionID = readUUID(statement, column: 0),
            let issueURL = readURL(statement, column: 2),
            let kind = readKind(statement, column: 4)
        else { return nil }

        let issueNumber = Int(sqlite3_column_int64(statement, 1))
        let title = readText(statement, column: 3) ?? ""
        let body = readText(statement, column: 5) ?? ""
        let deviceID = readText(statement, column: 6) ?? ""
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        let submittedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        let latestReplyAt: Date?
        if sqlite3_column_type(statement, 9) == SQLITE_NULL {
            latestReplyAt = nil
        } else {
            latestReplyAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
        }
        let replyCount = Int(sqlite3_column_int64(statement, 10))
        let readReplyCount = Int(sqlite3_column_int64(statement, 11))

        return SubmissionRecord(
            submissionID: submissionID,
            issueNumber: issueNumber,
            issueURL: issueURL,
            title: title,
            kind: kind,
            body: body,
            deviceID: deviceID,
            createdAt: createdAt,
            submittedAt: submittedAt,
            latestReplyAt: latestReplyAt,
            replyCount: replyCount,
            readReplyCount: readReplyCount
        )
    }

    private static func readText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func readUUID(_ statement: OpaquePointer, column: Int32) -> UUID? {
        guard let text = readText(statement, column: column) else { return nil }
        return UUID(uuidString: text)
    }

    private static func readURL(_ statement: OpaquePointer, column: Int32) -> URL? {
        guard let text = readText(statement, column: column) else { return nil }
        return URL(string: text)
    }

    private static func readKind(_ statement: OpaquePointer, column: Int32) -> ReportKind? {
        guard let text = readText(statement, column: column) else { return nil }
        return ReportKind(rawValue: text)
    }
}
