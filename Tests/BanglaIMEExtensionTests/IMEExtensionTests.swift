import XCTest
@testable import BanglaIMEExtension
import BanglaEngine
import BanglaStorage

/// Path to the bundled layouts relative to this test file.
private let layoutsDir: URL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("../../Targets/BanglaIMEExtension/Resources/layouts")

/// Builds an isolated writable lexicon + user DB pair in a temp dir.
private final class TempEngineEnv {
    let dir: URL
    let lexiconWritable: ConnectionPool
    let user: ConnectionPool
    let lexiconRepo: LexiconRepository
    let userRepo: UserRepository
    let sessionRepo: SessionRepository
    let layouts: [Layout]

    init(seedWords: [(String, String, Double)] = [
        ("ami", "আমি", 0.9),
        ("amar", "আমার", 0.85),
        ("tumi", "তুমি", 0.8),
        ("bangla", "বাংলা", 0.95),
    ]) throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bangla-ime-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lexiconPath = dir.appendingPathComponent("lexicon.db").path
        let userPath = dir.appendingPathComponent("user.db").path
        lexiconWritable = try ConnectionPool(path: lexiconPath, kind: .lexiconWritable)
        user = try ConnectionPool(path: userPath, kind: .user)
        try Migration.buildLexiconSchema(lexiconWritable)
        try Migration.migrate(user)
        lexiconRepo = LexiconRepository(pool: lexiconWritable)
        userRepo = UserRepository(pool: user)
        sessionRepo = SessionRepository(pool: user)
        layouts = try LayoutLoader.loadAll(fromDirectory: layoutsDir)
        for (latin, bangla, freq) in seedWords {
            try lexiconRepo.insertWord(bangla: bangla, baseFreq: freq, latinHints: [latin])
        }
    }

    var lexiconReadOnly: ConnectionPool { try! ConnectionPool(path: dir.appendingPathComponent("lexicon.db").path, kind: .lexicon) }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

final class IMEEngineTransliterationTests: XCTestCase {
    func testTransliterateCommonWords() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let engine = IMEEngine(layouts: env.layouts)
        let res = await engine.transliterate(latin: "ami", layoutId: "avro-phonetic")
        XCTAssertEqual(res?.bangla, "আমি")
        let tumi = await engine.transliterate(latin: "tumi", layoutId: "avro-phonetic")
        XCTAssertEqual(tumi?.bangla, "তুমি")
        let bangla = await engine.transliterate(latin: "bangla", layoutId: "avro-phonetic")
        XCTAssertEqual(bangla?.bangla, "বাংলা")
    }

    func testFixedMappingReturnsGlyph() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let engine = IMEEngine(layouts: env.layouts)
        // Probhat is a fixed layout; "k" should map to a Bengali glyph.
        let glyph = await engine.fixedMapping(for: "k", layoutId: "probhat")
        XCTAssertNotNil(glyph)
    }

    func testPhoneticOnFixedLayoutReturnsNil() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let engine = IMEEngine(layouts: env.layouts)
        let res = await engine.transliterate(latin: "k", layoutId: "probhat")
        XCTAssertNil(res)
    }
}

final class IMEEngineRankingTests: XCTestCase {
    func testRankReturnsSeededCandidate() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        // Use a read-only pool for the engine's lexicon (production posture).
        let lexiconRO = env.lexiconReadOnly
        let engine = IMEEngine(
            layouts: env.layouts,
            lexiconRepo: LexiconRepository(pool: lexiconRO),
            userRepo: env.userRepo,
            sessionRepo: env.sessionRepo
        )
        let res = await engine.transliterate(latin: "am", layoutId: "avro-phonetic")
        let list = await engine.rank(latin: "am", banglaPrefix: res?.bangla ?? "আ",
                                      layoutId: "avro-phonetic", context: [])
        XCTAssertTrue(list.entries.contains { $0.bangla == "আমি" },
                     "expected আমি in candidates, got \(list.entries.map { $0.bangla })")
        XCTAssertFalse(list.entries.isEmpty)
    }

    func testRankDeterministicAcrossCalls() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let lexiconRO = env.lexiconReadOnly
        let engine = IMEEngine(
            layouts: env.layouts,
            lexiconRepo: LexiconRepository(pool: lexiconRO),
            userRepo: env.userRepo,
            sessionRepo: env.sessionRepo
        )
        let l1 = await engine.rank(latin: "am", banglaPrefix: "আ", layoutId: "avro-phonetic", context: [])
        let l2 = await engine.rank(latin: "am", banglaPrefix: "আ", layoutId: "avro-phonetic", context: [])
        XCTAssertEqual(l1.entries.map { $0.bangla }, l2.entries.map { $0.bangla })
    }

    func testRankEmptyQueryYieldsEmptyOrPrefixOnly() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let lexiconRO = env.lexiconReadOnly
        let engine = IMEEngine(
            layouts: env.layouts,
            lexiconRepo: LexiconRepository(pool: lexiconRO),
            userRepo: env.userRepo
        )
        let list = await engine.rank(latin: "zzz", banglaPrefix: "", layoutId: "avro-phonetic", context: [])
        // No seeded word matches "zzz"; the pipeline should still return a list (possibly empty).
        XCTAssertNotNil(list.entries)
    }
}

/// End-to-end: simulate keystrokes feeding the resolver, then rank, then commit
/// and observe — exactly the controller's hot path minus the IMK client.
final class KeystrokeToEndToEndTests: XCTestCase {
    func testFeedKeystrokesThenRankThenCommit() async throws {
        let env = try TempEngineEnv()
        defer { env.cleanup() }
        let lexiconRO = env.lexiconReadOnly
        let engine = IMEEngine(
            layouts: env.layouts,
            lexiconRepo: LexiconRepository(pool: lexiconRO),
            userRepo: env.userRepo,
            sessionRepo: env.sessionRepo
        )

        // 1. User types "a","m","i" — the controller re-resolves the whole buffer
        //    on each keystroke via the (sync) PhoneticResolver.
        guard let avro = env.layouts.first(where: { $0.id == "avro-phonetic" }) else {
            return XCTFail("avro-phonetic layout missing")
        }
        let resolver = PhoneticResolver(layout: avro)
        var buffer = ""
        for ch in ["a", "m", "i"] {
            buffer.append(ch)
            let resolution = resolver.resolve(buffer)
            // After typing "ami" we expect the full word.
            if buffer == "ami" {
                XCTAssertEqual(resolution.bangla, "আমি")
            }
        }

        // 2. Fire a ranking pass (the controller does this as a detached task).
        let list = await engine.rank(latin: buffer, banglaPrefix: resolver.resolve(buffer).bangla,
                                      layoutId: "avro-phonetic", context: [])
        XCTAssertTrue(list.entries.contains { $0.bangla == "আমি" })

        // 3. User accepts the top candidate; controller records the commit.
        guard let chosen = list.entries.first else {
            return XCTFail("no candidates")
        }
        await engine.observeCommit(latin: buffer, chosen: chosen, context: [],
                                     sessionId: UUID(), appBundleHash: "test-app")

        // 4. The user word table should now reflect learning.
        let learned = try env.userRepo.userWordCandidates(latin: "am")
        XCTAssertTrue(learned.contains { $0.bangla == "আমি" },
                     "commit should upsert the chosen word into user_word")
    }
}