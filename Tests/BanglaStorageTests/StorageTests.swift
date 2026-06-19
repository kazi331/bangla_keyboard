import XCTest
@testable import BanglaStorage
import BanglaEngine

/// Builds an isolated writable lexicon + user DB pair in a temp dir per test.
private final class TempDB {
    let dir: URL
    let lexiconPath: String
    let userPath: String
    let lexiconWritable: ConnectionPool
    let user: ConnectionPool

    init() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bangla-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lexiconPath = dir.appendingPathComponent("lexicon.db").path
        userPath = dir.appendingPathComponent("user.db").path
        lexiconWritable = try ConnectionPool(path: lexiconPath, kind: .lexiconWritable)
        user = try ConnectionPool(path: userPath, kind: .user)
        try Migration.buildLexiconSchema(lexiconWritable)
        try Migration.migrate(user)
    }

    var lexiconReadOnly: ConnectionPool { try! ConnectionPool(path: lexiconPath, kind: .lexicon) }
    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

final class ConnectionPoolTests: XCTestCase {
    func testOpenAndExec() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        try tmp.user.connection().exec("CREATE TABLE IF NOT EXISTS t (x INTEGER);")
        try tmp.user.connection().exec("INSERT INTO t (x) VALUES (42);")
        let rows = try tmp.user.connection().query("SELECT x FROM t;", map: { $0.int(0) })
        XCTAssertEqual(rows, [42])
    }

    func testReadOnlyLexiconRejectsWrites() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let ro = tmp.lexiconReadOnly
        XCTAssertThrowsError(try ro.connection().exec("INSERT INTO word (bangla, base_freq) VALUES ('x', 1);"))
    }
}

final class MigrationTests: XCTestCase {
    func testMigrateSetsVersion() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let version = try tmp.user.connection()
            .query("SELECT MAX(version) FROM schema_version;", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(version, Schema.userVersion)
    }

    func testMigrateIdempotent() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        // Running again must not error nor bump version past the target.
        try Migration.migrate(tmp.user)
        let version = try tmp.user.connection()
            .query("SELECT MAX(version) FROM schema_version;", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(version, Schema.userVersion)
    }

    func testFTSTriggersPopulateUserFTS() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami")
        let rows = try tmp.user.connection()
            .query("SELECT COUNT(*) FROM user_word_fts WHERE user_word_fts MATCH 'ami';", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(rows, 1)
    }
}

final class LexiconRepositoryTests: XCTestCase {
    func testInsertAndCount() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = LexiconRepository(pool: tmp.lexiconWritable)
        try repo.insertWord(bangla: "আমি", baseFreq: 0.9, latinHints: ["ami"])
        try repo.insertWord(bangla: "তুমি", baseFreq: 0.8, latinHints: ["tumi"])
        XCTAssertEqual(try repo.count(), 2)
    }

    func testCandidatesByLatinPrefix() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = LexiconRepository(pool: tmp.lexiconWritable)
        try repo.insertWord(bangla: "আমি", baseFreq: 0.9, latinHints: ["ami"])
        try repo.insertWord(bangla: "আমার", baseFreq: 0.8, latinHints: ["amar"])
        try repo.insertWord(bangla: "তুমি", baseFreq: 0.7, latinHints: ["tumi"])
        let cands = try repo.candidates(latin: "am", layoutId: "avro-phonetic", limit: 16)
        XCTAssertTrue(cands.contains { $0.bangla == "আমি" })
        XCTAssertTrue(cands.contains { $0.bangla == "আমার" })
        XCTAssertFalse(cands.contains { $0.bangla == "তুমি" })
    }

    func testPhonemeMapInsertAndQuery() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = LexiconRepository(pool: tmp.lexiconWritable)
        try repo.insertPhonemeMapping(latin: "k", bangla: "ক", ruleSet: "avro-phonetic")
        let cands = try repo.candidates(latin: "k", layoutId: "avro-phonetic", limit: 16)
        XCTAssertTrue(cands.contains { $0.bangla == "ক" })
    }
}

final class UserRepositoryTests: XCTestCase {
    func testUpsertIncrementsUseCount() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami")
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami")
        let rows = try tmp.user.connection()
            .query("SELECT use_count FROM user_word WHERE bangla = 'আমি';", map: { $0.int(0) })
        XCTAssertEqual(rows, [2])
    }

    func testUserWordCandidates() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami", customFreq: 0.6)
        let cands = try repo.userWordCandidates(latin: "am")
        XCTAssertTrue(cands.contains { $0.bangla == "আমি" })
    }

    func testNgramSuggestions() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.observeNgram(context: ["আমি", "ভালো"], token: "আছি")
        let sugg = try repo.ngramSuggestions(context: ["আমি", "ভালো"], prefix: "আ")
        XCTAssertTrue(sugg.contains { $0.bangla == "আছি" })
    }

    func testRecordCommit() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.recordCommit(sessionId: "s1", typedLatin: "ami", chosenBangla: "আমি",
                               chosenRank: 0, chosenSource: "lexicon", appBundleHash: "app")
        let n = try tmp.user.connection().query("SELECT COUNT(*) FROM commit_log;", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(n, 1)
    }

    func testBurnHistoryClears() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.recordCommit(sessionId: "s1", typedLatin: "ami", chosenBangla: "আমি",
                               chosenRank: 0, chosenSource: "lexicon", appBundleHash: nil)
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami")
        try repo.burnHistory()
        let commits = try tmp.user.connection().query("SELECT COUNT(*) FROM commit_log;", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(commits, 0)
    }
}

final class BackupTests: XCTestCase {
    func testVacuumIntoBackup() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = UserRepository(pool: tmp.user)
        try repo.upsertUserWord(bangla: "আমি", latinHint: "ami")
        let backupURL = tmp.dir.appendingPathComponent("backup.db")
        try repo.backup(to: backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        // Backup should contain the row.
        let pool = try ConnectionPool(path: backupURL.path, kind: .lexiconWritable)
        let n = try pool.connection().query("SELECT COUNT(*) FROM user_word;", map: { $0.int(0) }).first ?? 0
        XCTAssertEqual(n, 1)
    }
}

final class FTSPerformanceTests: XCTestCase {
    func testPrefixSearchLatency() throws {
        let tmp = try TempDB()
        defer { tmp.cleanup() }
        let repo = LexiconRepository(pool: tmp.lexiconWritable)
        // Seed a few thousand rows.
        for i in 0..<2000 {
            try repo.insertWord(bangla: "শব্দ\(i)", baseFreq: Double(2000 - i) / 2000.0,
                                latinHints: ["word\(i)"])
        }
        let ro = tmp.lexiconReadOnly
        let search = PrefixSearch(pool: ro)
        let start = Date()
        for _ in 0..<50 {
            _ = try search.latinPrefix("word", limit: 256)
        }
        let ms = Date().timeIntervalSince(start) * 1000 / 50
        // Generous budget; this is a smoke test that prefix lookup is sub-millisecond-ish.
        XCTAssertLessThan(ms, 20.0, "avg prefix search \(ms)ms exceeded budget")
    }
}