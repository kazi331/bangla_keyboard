import Foundation
import SQLite3
import BanglaEngine

/// FTS5-backed prefix search on the lexicon.
public final class PrefixSearch: @unchecked Sendable {
    public let pool: ConnectionPool

    public init(pool: ConnectionPool) {
        self.pool = pool
    }

    /// Prefix search on `latin_fts`. Returns up to `limit` (word_id, latin, bangla).
    public func latinPrefix(_ query: String, limit: Int = 256) throws -> [(wordId: Int, latin: String, bangla: String)] {
        guard !query.isEmpty else { return [] }
        let conn = try pool.connection()
        // FTS5 prefix syntax: term followed by '*' matches prefix.
        let ftsQuery = fts5Escape(query) + "*"
        return try conn.query(
            """
            SELECT lf.word_id, lf.latin, w.bangla
            FROM latin_fts AS lf
            JOIN word AS w ON w.id = lf.word_id
            WHERE latin_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """,
            params: [.text(ftsQuery), .int(limit)]
        ) { row in
            (wordId: row.int(0), latin: row.text(1), bangla: row.text(2))
        }
    }

    /// Prefix search on `word_fts` (Bangla output side).
    public func banglaPrefix(_ prefix: String, limit: Int = 256) throws -> [(wordId: Int, bangla: String, baseFreq: Double)] {
        guard !prefix.isEmpty else { return [] }
        let conn = try pool.connection()
        let ftsQuery = fts5Escape(prefix) + "*"
        return try conn.query(
            """
            SELECT rowid, bangla, ''
            FROM word_fts
            WHERE word_fts MATCH ?
            LIMIT ?;
            """,
            params: [.text(ftsQuery), .int(limit)]
        ) { row in
            // We need base_freq via join on word.id == rowid (FTS rowid mirrors word.id).
            (wordId: row.int(0), bangla: row.text(1), baseFreq: 0.0)
        }
    }

    /// Escape a string for FTS5 MATCH (strip control chars; keep ASCII letters/digits).
    private func fts5Escape(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch) }
        }
        if out.isEmpty { out = "x" }   // never empty
        return out
    }
}