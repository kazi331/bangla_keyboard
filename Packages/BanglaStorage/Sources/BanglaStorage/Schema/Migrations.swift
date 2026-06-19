import Foundation
import SQLite3

/// Schema definitions and migration runner.
public enum Schema {
    public static let userVersion: Int = 2

    public static let lexiconDDL: [String] = [
        """
        CREATE TABLE IF NOT EXISTS word (
            id            INTEGER PRIMARY KEY,
            bangla        TEXT NOT NULL,
            ipa_hint      TEXT,
            base_freq     REAL NOT NULL,
            is_proper     INTEGER NOT NULL DEFAULT 0,
            source        TEXT NOT NULL DEFAULT 'manual'
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_word_bangla ON word(bangla COLLATE BINARY);",
        """
        CREATE TABLE IF NOT EXISTS phoneme_map (
            id            INTEGER PRIMARY KEY,
            latin         TEXT NOT NULL,
            bangla        TEXT NOT NULL,
            rule_set      TEXT NOT NULL,
            weight        REAL NOT NULL DEFAULT 1.0,
            priority      INTEGER NOT NULL DEFAULT 100
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_pm_latin_rule ON phoneme_map(latin, rule_set, priority);",
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS word_fts USING fts5(
            bangla,
            tokenize = 'unicode61 remove_diacritics 0'
        );
        """,
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS latin_fts USING fts5(
            latin,
            word_id UNINDEXED,
            tokenize = 'unicode61'
        );
        """,
    ]

    public static let userDDL: [String] = [
        """
        CREATE TABLE IF NOT EXISTS schema_version (
            version    INTEGER PRIMARY KEY,
            applied_at INTEGER NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS user_word (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            bangla        TEXT NOT NULL UNIQUE,
            latin_hint    TEXT,
            custom_freq   REAL NOT NULL DEFAULT 0.5,
            created_at    INTEGER NOT NULL,
            last_used_at  INTEGER NOT NULL,
            use_count     INTEGER NOT NULL DEFAULT 0
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_uw_bangla ON user_word(bangla);",
        "CREATE INDEX IF NOT EXISTS idx_uw_latin ON user_word(latin_hint);",
        """
        CREATE TABLE IF NOT EXISTS ngram (
            context       TEXT NOT NULL,
            token         TEXT NOT NULL,
            count         INTEGER NOT NULL DEFAULT 1,
            last_seen     INTEGER NOT NULL,
            PRIMARY KEY (context, token)
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_ngram_context ON ngram(context);",
        """
        CREATE TABLE IF NOT EXISTS commit_log (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id    TEXT NOT NULL,
            typed_latin   TEXT NOT NULL,
            chosen_bangla TEXT NOT NULL,
            chosen_rank   INTEGER NOT NULL,
            chosen_source TEXT NOT NULL,
            app_bundle    TEXT,
            ts            INTEGER NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_cl_ts ON commit_log(ts);",
        "CREATE INDEX IF NOT EXISTS idx_cl_latin ON commit_log(typed_latin);",
        """
        CREATE TABLE IF NOT EXISTS layout_pref (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS autoreplace (
            trigger TEXT PRIMARY KEY,
            output  TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS app_layout (
            app_bundle TEXT PRIMARY KEY,
            layout     TEXT NOT NULL
        );
        """,
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS user_word_fts USING fts5(
            bangla, latin_hint, content='user_word', content_rowid='id'
        );
        """,
    ]
}

public enum Migration {
    /// Apply user-schema migrations up to `Schema.userVersion`.
    public static func migrate(_ pool: ConnectionPool) throws {
        let conn = try pool.connection()
        try conn.exec("BEGIN;")
        do {
            // Apply all base DDL first. Every statement is idempotent
            // (IF NOT EXISTS / external-content FTS references the already-created
            // base tables), so re-running migrate() on an existing DB is a no-op.
            for ddl in Schema.userDDL {
                try conn.exec(ddl)
            }
            let current: Int = try conn.query(
                "SELECT COALESCE(MAX(version), 0) AS v FROM schema_version;", params: []
            ) { row in row.int(0) }.first ?? 0

            if current < 1 {
                try conn.run(
                    "INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (?, ?);",
                    params: [.int(1), .int(Int(Date().timeIntervalSince1970))]
                )
            }
            if current < 2 {
                // v2: add user_word_fts triggers for content-sync (FTS5 external
                // content). user_word and user_word_fts already exist from the DDL.
                try conn.exec("""
                CREATE TRIGGER IF NOT EXISTS user_word_ai AFTER INSERT ON user_word BEGIN
                    INSERT INTO user_word_fts(rowid, bangla, latin_hint)
                    VALUES (new.id, new.bangla, COALESCE(new.latin_hint, ''));
                END;
                """)
                try conn.exec("""
                CREATE TRIGGER IF NOT EXISTS user_word_ad AFTER DELETE ON user_word BEGIN
                    INSERT INTO user_word_fts(user_word_fts, rowid, bangla, latin_hint)
                    VALUES ('delete', old.id, old.bangla, COALESCE(old.latin_hint, ''));
                END;
                """)
                try conn.exec("""
                CREATE TRIGGER IF NOT EXISTS user_word_au AFTER UPDATE ON user_word BEGIN
                    INSERT INTO user_word_fts(user_word_fts, rowid, bangla, latin_hint)
                    VALUES ('delete', old.id, old.bangla, COALESCE(old.latin_hint, ''));
                    INSERT INTO user_word_fts(rowid, bangla, latin_hint)
                    VALUES (new.id, new.bangla, COALESCE(new.latin_hint, ''));
                END;
                """)
                try conn.run(
                    "INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (?, ?);",
                    params: [.int(2), .int(Int(Date().timeIntervalSince1970))]
                )
            }
            try conn.exec("COMMIT;")
        } catch {
            try? conn.exec("ROLLBACK;")
            throw error
        }
    }

    /// Build the lexicon schema (idempotent; no migration table needed).
    public static func buildLexiconSchema(_ pool: ConnectionPool) throws {
        let conn = try pool.connection()
        for ddl in Schema.lexiconDDL {
            try conn.exec(ddl)
        }
    }
}