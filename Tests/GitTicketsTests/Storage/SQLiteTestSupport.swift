import Foundation
import SQLite3

/// A raw SQLite connection for tests that need to shape a database file
/// outside ``SubmissionCache`` — build an old schema, hold a lock, drop a
/// table.
final class SQLiteHandle {
    struct Failure: Error, CustomStringConvertible {
        let status: Int32
        let message: String
        var description: String { "SQLite \(status): \(message)" }
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard status == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw Failure(status: status, message: message)
        }
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &error)
        guard status == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw Failure(status: status, message: message)
        }
    }
}

/// Runs `sql` on a short-lived connection to `path`.
func sqliteExec(_ path: String, _ sql: String) throws {
    try SQLiteHandle(path: path).exec(sql)
}
