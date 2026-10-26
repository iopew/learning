import Foundation
import SQLite3

public struct DatabaseError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    public init(message: String) {
        self.message = message
    }
}

enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

/// Minimal SQLite wrapper. Not thread-safe by itself: callers serialize access (ActivityStore holds a lock).
final class Database {
    private var handle: OpaquePointer?

    /// `readOnly`: for the `sql` command line, so a typo can't change anything.
    init(path: String, readOnly: Bool = false) throws {
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw DatabaseError(message: "open \(path): \(message)")
        }
        sqlite3_busy_timeout(handle, 3000)
        // A database opened from a file (a saved copy) must not run SQL functions hidden in its views or triggers.
        sqlite3_exec(handle, "PRAGMA trusted_schema=OFF;", nil, nil, nil)
    }

    deinit {
        sqlite3_close(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Rows changed by the last INSERT / UPDATE / DELETE.
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// Column names of a table (for schema upgrades).
    /// Runs any query and returns the column names and rows as text (for the `sql` command).
    func rawQuery(_ sql: String) throws -> (columns: [String], rows: [[String]]) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        let count = sqlite3_column_count(statement)
        let columns = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
        var rows: [[String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw lastError() }
            rows.append((0..<count).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "NULL"
            })
        }
        return (columns, rows)
    }

    func columns(of table: String) throws -> Set<String> {
        Set(try query("PRAGMA table_info(\(table))") { $0.text(1) })
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DatabaseError(message: message)
        }
    }

    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw lastError() }
    }

    func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw lastError() }
            result.append(map(Row(statement: statement)))
        }
        return result
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            switch param {
            case .int(let value): sqlite3_bind_int64(statement, position, value)
            case .double(let value): sqlite3_bind_double(statement, position, value)
            case .text(let value): sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    private func lastError() -> DatabaseError {
        DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
    }
}

struct Row {
    let statement: OpaquePointer?

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
