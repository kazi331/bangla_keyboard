import Foundation
import SQLite3

public enum DatabaseKind {
    case lexicon            // read-only, mmap'd, no WAL
    case lexiconWritable    // read-write, no journal (build-time only)
    case user               // read-write, WAL
}

public final class ConnectionPool: @unchecked Sendable {
    public let path: String
    public let kind: DatabaseKind
    private let lock = NSLock()
    private var conn: SQLiteConnection?

    public init(path: String, kind: DatabaseKind) throws {
        self.path = path
        self.kind = kind
        self.conn = try ConnectionPool.open(path: path, kind: kind)
    }

    public func connection() throws -> SQLiteConnection {
        lock.lock(); defer { lock.unlock() }
        if let c = conn {
            return c
        }
        let c = try ConnectionPool.open(path: path, kind: kind)
        self.conn = c
        return c
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        conn = nil
    }

    static func open(path: String, kind: DatabaseKind) throws -> SQLiteConnection {
        var handle: OpaquePointer?
        let flags: Int32
        switch kind {
        case .lexicon:
            flags = SQLITE_OPEN_READONLY
        case .lexiconWritable, .user:
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        }
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError.openFailure(msg)
        }
        let c = SQLiteConnection(handle: handle!, path: path)
        switch kind {
        case .lexicon:
            try c.exec("PRAGMA journal_mode = OFF;")
            try c.exec("PRAGMA mmap_size = 268435456;")
            try c.exec("PRAGMA cache_size = -8000;")
            try c.exec("PRAGMA query_only = 1;")
        case .lexiconWritable:
            try c.exec("PRAGMA journal_mode = OFF;")
            try c.exec("PRAGMA synchronous = OFF;")
            try c.exec("PRAGMA cache_size = -20000;")
        case .user:
            try c.exec("PRAGMA journal_mode = WAL;")
            try c.exec("PRAGMA synchronous = NORMAL;")
            try c.exec("PRAGMA busy_timeout = 2000;")
            try c.exec("PRAGMA foreign_keys = ON;")
            try c.exec("PRAGMA mmap_size = 67108864;")
        }
        return c
    }
}