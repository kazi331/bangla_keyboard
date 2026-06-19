import Foundation
import SQLite3
import BanglaEngine

public final class LexiconRepository: @unchecked Sendable {
    public let pool: ConnectionPool
    public let phoneticSearch: PhoneticSearch

    public init(pool: ConnectionPool) {
        self.pool = pool
        self.phoneticSearch = PhoneticSearch(pool: pool, prefixSearch: PrefixSearch(pool: pool))
    }

    public func insertWord(bangla: String, baseFreq: Double, isProper: Bool = false, source: String = "manual", latinHints: [String] = []) throws {
        let conn = try pool.connection()
        try conn.run("BEGIN;")
        defer { try? conn.run("COMMIT;") }
        var id: Int = 0
        try conn.run(
            "INSERT INTO word (bangla, base_freq, is_proper, source) VALUES (?, ?, ?, ?);",
            params: [.text(bangla), .double(baseFreq), .int(isProper ? 1 : 0), .text(source)]
        )
        id = Int(sqlite3_last_insert_rowid(conn.handle))
        // word_fts
        try conn.run("INSERT INTO word_fts (bangla) VALUES (?);", params: [.text(bangla)])
        // latin_fts entries
        for hint in latinHints {
            try conn.run(
                "INSERT INTO latin_fts (latin, word_id) VALUES (?, ?);",
                params: [.text(hint.lowercased()), .int(id)]
            )
        }
    }

    public func insertPhonemeMapping(latin: String, bangla: String, ruleSet: String, weight: Double = 1.0, priority: Int = 100) throws {
        let conn = try pool.connection()
        try conn.run(
            "INSERT INTO phoneme_map (latin, bangla, rule_set, weight, priority) VALUES (?, ?, ?, ?, ?);",
            params: [.text(latin.lowercased()), .text(bangla), .text(ruleSet), .double(weight), .int(priority)]
        )
    }

    public func count() throws -> Int {
        let conn = try pool.connection()
        return try conn.query("SELECT COUNT(*) FROM word;") { row in row.int(0) }.first ?? 0
    }

    public func candidates(latin: String, layoutId: String, limit: Int = 256) throws -> [Candidate] {
        try phoneticSearch.search(latin: latin, layoutId: layoutId, limit: limit)
    }
}