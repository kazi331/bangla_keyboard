import Foundation
import SQLite3
import BanglaEngine

public final class UserRepository: @unchecked Sendable {
    public let pool: ConnectionPool

    public init(pool: ConnectionPool) {
        self.pool = pool
    }

    public func upsertUserWord(bangla: String, latinHint: String?, customFreq: Double = 0.3) throws {
        let conn = try pool.connection()
        let now = Int(Date().timeIntervalSince1970)
        try conn.run(
            """
            INSERT INTO user_word (bangla, latin_hint, custom_freq, created_at, last_used_at, use_count)
            VALUES (?, ?, ?, ?, ?, 1)
            ON CONFLICT(bangla) DO UPDATE SET
                use_count = use_count + 1,
                last_used_at = excluded.last_used_at,
                custom_freq = MAX(custom_freq, excluded.custom_freq);
            """,
            params: [.text(bangla), .text(latinHint ?? ""), .double(customFreq), .int(now), .int(now)]
        )
    }

    public func recordCommit(sessionId: String, typedLatin: String, chosenBangla: String, chosenRank: Int, chosenSource: String, appBundleHash: String?) throws {
        let conn = try pool.connection()
        let now = Int(Date().timeIntervalSince1970)
        try conn.run(
            """
            INSERT INTO commit_log (session_id, typed_latin, chosen_bangla, chosen_rank, chosen_source, app_bundle, ts)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            params: [.text(sessionId), .text(typedLatin), .text(chosenBangla), .int(chosenRank),
                     .text(chosenSource), .text(appBundleHash ?? ""), .int(now)]
        )
    }

    public func observeNgram(context: [String], token: String) throws {
        let conn = try pool.connection()
        let key = context.suffix(2).joined(separator: " ")
        let now = Int(Date().timeIntervalSince1970)
        try conn.run(
            """
            INSERT INTO ngram (context, token, count, last_seen)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(context, token) DO UPDATE SET
                count = count + 1,
                last_seen = excluded.last_seen;
            """,
            params: [.text(key), .text(token), .int(now)]
        )
    }

    public func userWordCandidates(latin: String, limit: Int = 128) throws -> [Candidate] {
        guard !latin.isEmpty else { return [] }
        let conn = try pool.connection()
        let ftsQuery = escape(latin) + "*"
        return try conn.query(
            """
            SELECT uw.id, uw.bangla, COALESCE(uw.latin_hint, ''), uw.custom_freq, uw.use_count, uw.last_used_at
            FROM user_word_fts
            JOIN user_word AS uw ON uw.id = user_word_fts.rowid
            WHERE user_word_fts MATCH ?
            LIMIT ?;
            """,
            params: [.text(ftsQuery), .int(limit)]
        ) { row in
            Candidate(
                bangla: row.text(1),
                latinHint: row.text(2),
                source: .user,
                score: row.double(3),
                useCount: row.int(4),
                lastUsedAt: Date(timeIntervalSince1970: TimeInterval(row.int(5)))
            )
        }
    }

    public func ngramSuggestions(context: [String], prefix: String, limit: Int = 64) throws -> [Candidate] {
        let conn = try pool.connection()
        let key = context.suffix(2).joined(separator: " ")
        let likePrefix = escapeLike(prefix) + "%"
        return try conn.query(
            """
            SELECT token, count FROM ngram
            WHERE context = ? AND token LIKE ? ESCAPE '\\'
            ORDER BY count DESC
            LIMIT ?;
            """,
            params: [.text(key), .text(likePrefix), .int(limit)]
        ) { row in
            Candidate(
                bangla: row.text(0),
                latinHint: "",
                source: .lm,
                score: Double(row.int(1))
            )
        }
    }

    public func burnHistory() throws {
        let conn = try pool.connection()
        try conn.run("DELETE FROM commit_log;")
        try conn.run("DELETE FROM ngram;")
        try conn.run("VACUUM;")
    }

    public func backup(to url: URL) throws {
        let conn = try pool.connection()
        try conn.run("VACUUM INTO ?;", params: [.text(url.path)])
    }

    private func escape(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch) }
        }
        return out.isEmpty ? "x" : out
    }

    private func escapeLike(_ s: String) -> String {
        var safe = ""
        for ch in s {
            if ch == "\\" || ch == "%" || ch == "_" { safe.append("\\") }
            safe.append(ch)
        }
        return safe
    }
}