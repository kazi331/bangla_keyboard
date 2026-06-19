import Foundation
import SQLite3

/// Stores per-session metadata (not the commit log; that lives in UserRepository).
/// Kept separate for future telemetry partitioning.
public final class SessionRepository: @unchecked Sendable {
    public let pool: ConnectionPool
    public init(pool: ConnectionPool) { self.pool = pool }

    public func setLayout(_ layoutId: String) throws {
        let conn = try pool.connection()
        try conn.run(
            "INSERT OR REPLACE INTO layout_pref (key, value) VALUES ('active_layout', ?);",
            params: [.text(layoutId)]
        )
    }

    public func currentLayout() throws -> String? {
        let conn = try pool.connection()
        return try conn.query(
            "SELECT value FROM layout_pref WHERE key = 'active_layout';"
        ) { row in row.text(0) }.first
    }

    public func setAppLayout(appBundleHash: String, layout: String) throws {
        let conn = try pool.connection()
        try conn.run(
            "INSERT OR REPLACE INTO app_layout (app_bundle, layout) VALUES (?, ?);",
            params: [.text(appBundleHash), .text(layout)]
        )
    }

    public func appLayout(for appBundleHash: String) throws -> String? {
        let conn = try pool.connection()
        return try conn.query(
            "SELECT layout FROM app_layout WHERE app_bundle = ?;",
            params: [.text(appBundleHash)]
        ) { row in row.text(0) }.first
    }

    public func addAutoreplace(trigger: String, output: String) throws {
        let conn = try pool.connection()
        try conn.run(
            "INSERT OR REPLACE INTO autoreplace (trigger, output, enabled) VALUES (?, ?, 1);",
            params: [.text(trigger), .text(output)]
        )
    }

    public func autoreplaces() throws -> [String: String] {
        let conn = try pool.connection()
        let rows = try conn.query(
            "SELECT trigger, output FROM autoreplace WHERE enabled = 1;"
        ) { row in (row.text(0), row.text(1)) }
        var dict: [String: String] = [:]
        for r in rows { dict[r.0] = r.1 }
        return dict
    }
}