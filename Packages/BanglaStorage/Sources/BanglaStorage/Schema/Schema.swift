import Foundation
import SQLite3

public enum SQLiteError: Error {
    case openFailure(String)
    case execFailure(String)
    case prepareFailure(String)
    case stepFailure(String)
    case bindFailure(String)
    case migrationFailure(String)
}

/// Opaque handle wrapping a sqlite3*. Use only within ConnectionPool.
public final class SQLiteConnection: @unchecked Sendable {
    public let handle: OpaquePointer
    public let path: String
    private let queue: DispatchQueue
    private let lock = NSLock()

    init(handle: OpaquePointer, path: String) {
        self.handle = handle
        self.path = path
        self.queue = DispatchQueue(label: "com.bangla ime.storage.\(UUID().uuidString)")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Execute a single statement (no params). Throws on failure.
    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.execFailure("sqlite3_exec failed (\(rc)): \(msg). SQL: \(sql)")
        }
    }

    /// Run a parameterized statement. Bind order matches `params`.
    public func run(_ sql: String, params: [SQLValue] = []) throws {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailure("prepare failed: \(String(cString: sqlite3_errmsg(handle))). SQL: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        try bindAll(stmt: stmt, params: params)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw SQLiteError.stepFailure("step failed (\(rc)): \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    /// Query and map rows. Returns array of mapped values.
    public func query<T>(_ sql: String, params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailure("prepare failed: \(String(cString: sqlite3_errmsg(handle))). SQL: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        try bindAll(stmt: stmt, params: params)
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(map(Row(stmt: stmt!)))
        }
        return out
    }

    private func bindAll(stmt: OpaquePointer?, params: [SQLValue]) throws {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null:
                sqlite3_bind_null(stmt, idx)
            case .int(let v):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(v))
            case .double(let v):
                sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                sqlite3_bind_text(stmt, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let v):
                _ = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
        }
    }
}

public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int)
    case double(Double)
    case text(String)
    case blob(Data)
}

public struct Row {
    public let stmt: OpaquePointer
    public func int(_ i: Int32) -> Int   { Int(sqlite3_column_int64(stmt, i)) }
    public func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    public func text(_ i: Int32) -> String {
        if let c = sqlite3_column_text(stmt, i) {
            return String(cString: c)
        }
        return ""
    }
    public func isNull(_ i: Int32) -> Bool {
        sqlite3_column_type(stmt, i) == SQLITE_NULL
    }
}