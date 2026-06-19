import Foundation
import SQLite3
import BanglaEngine

/// Phonetic search combines FTS5 latin prefix with rule-set expansion.
public final class PhoneticSearch: @unchecked Sendable {
    public let pool: ConnectionPool
    public let prefixSearch: PrefixSearch

    public init(pool: ConnectionPool, prefixSearch: PrefixSearch) {
        self.pool = pool
        self.prefixSearch = prefixSearch
    }

    public func search(latin: String, layoutId: String, limit: Int = 256) throws -> [Candidate] {
        let rows = try prefixSearch.latinPrefix(latin, limit: limit)
        var seen: Set<String> = []
        var out: [Candidate] = []
        for r in rows {
            if seen.contains(r.bangla) { continue }
            seen.insert(r.bangla)
            out.append(Candidate(
                bangla: r.bangla,
                latinHint: r.latin,
                source: .lexicon,
                score: 0.5
            ))
        }
        // Also pull candidates from phoneme_map for this rule_set.
        let conn = try pool.connection()
        let mapRows = try conn.query(
            """
            SELECT latin, bangla, weight FROM phoneme_map
            WHERE rule_set = ? AND latin LIKE ? ESCAPE '\\'
            ORDER BY priority, weight DESC
            LIMIT ?;
            """,
            params: [.text(layoutId), .text(escapeLike(latin)), .int(limit)]
        ) { row in
            (latin: row.text(0), bangla: row.text(1), weight: row.double(2))
        }
        for r in mapRows {
            if seen.contains(r.bangla) { continue }
            seen.insert(r.bangla)
            out.append(Candidate(
                bangla: r.bangla,
                latinHint: r.latin,
                source: .lexicon,
                score: r.weight
            ))
        }
        return out
    }

    private func escapeLike(_ s: String) -> String {
        // For LIKE we want prefix match: "abc%"
        var safe = ""
        for ch in s {
            if ch == "\\" || ch == "%" || ch == "_" { safe.append("\\") }
            safe.append(ch)
        }
        return safe + "%"
    }
}