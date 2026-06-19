import XCTest
@testable import BanglaEngine

/// Path to the bundled layouts relative to this test file.
private let layoutsDir: URL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("../../Targets/BanglaIMEExtension/Resources/layouts")

final class ResolverTests: XCTestCase {
    func loadAvro() throws -> Layout {
        try LayoutLoader.load(from: layoutsDir.appendingPathComponent("avro-phonetic.json"))
    }

    func testIndependentVowelAtStart() throws {
        let layout = try loadAvro()
        let r = PhoneticResolver(layout: layout)
        // "a" with no preceding consonant -> independent vowel আ
        XCTAssertEqual(r.resolve("a").bangla, "আ")
        // "ka" -> ক + া (kar after consonant)
        XCTAssertEqual(r.resolve("ka").bangla, "কা")
    }

    func testAvroParityCommonWords() throws {
        let layout = try loadAvro()
        let r = PhoneticResolver(layout: layout)
        XCTAssertEqual(r.resolve("ami").bangla, "আমি")
        XCTAssertEqual(r.resolve("tumi").bangla, "তুমি")
        XCTAssertEqual(r.resolve("amar").bangla, "আমার")
        XCTAssertEqual(r.resolve("bangla").bangla, "বাংলা")
        XCTAssertEqual(r.resolve("bangladesh").bangla, "বাংলাদেশ")
        XCTAssertEqual(r.resolve("kichu").bangla, "কিছু")
    }

    func testConsonantClusters() throws {
        let layout = try loadAvro()
        let r = PhoneticResolver(layout: layout)
        XCTAssertEqual(r.resolve("kSh").bangla, "ক্ষ")
        XCTAssertEqual(r.resolve("pr").bangla, "প্র")
        XCTAssertEqual(r.resolve("tr").bangla, "ত্র")
    }

    func testDigitsAndDanda() throws {
        let layout = try loadAvro()
        let r = PhoneticResolver(layout: layout)
        XCTAssertEqual(r.resolve("1").bangla, "১")
        XCTAssertEqual(r.resolve("..").bangla, "।")
        XCTAssertEqual(r.resolve("...").bangla, "॥")
    }

    func testAlternatesCollected() throws {
        let layout = try loadAvro()
        let r = PhoneticResolver(layout: layout)
        // "rri" must be consumed by a rule (not passed through as the literal "rri").
        let res = r.resolve("rri")
        XCTAssertNotEqual(res.bangla, "rri")
        XCTAssertFalse(res.bangla.isEmpty, "expected a Bengali output, got empty")
    }
}

final class NormalizerTests: XCTestCase {
    func testNFCCanonicalization() {
        // Decomposed ক + ি should compose to কি.
        let decomposed = "ক" + "\u{09BF}"
        let normalized = Normalizer.normalize(decomposed)
        XCTAssertEqual(normalized, "কি")
    }

    func testDottedCircleStripped() {
        let withCircle = "\u{25CC}\u{09BF}"  // dotted circle + i-kar
        let normalized = Normalizer.normalize(withCircle)
        XCTAssertFalse(normalized.contains("\u{25CC}"))
    }

    func testZWJRunsCollapsed() {
        let zwj = "\u{200C}"
        let collapsed = Normalizer.normalize(zwj + zwj + zwj + "ক")
        XCTAssertEqual(collapsed.unicodeScalars.filter { $0.value == 0x200C }.count, 1)
    }

    func testIsCanonicalBangla() {
        XCTAssertTrue(Normalizer.isCanonicalBangla("আমার নাম"))
        XCTAssertFalse(Normalizer.isCanonicalBangla("hello"))
        XCTAssertTrue(Normalizer.isCanonicalBangla("১২৩"))
    }
}

final class CompositionBufferTests: XCTestCase {
    func testAppendAndBangla() {
        var buf = CompositionBuffer()
        buf.append(latin: "am", bangla: "আম")
        XCTAssertEqual(buf.latin, "am")
        XCTAssertEqual(buf.bangla, "আম")
    }

    func testReplaceCurrent() {
        var buf = CompositionBuffer()
        buf.append(latin: "am", bangla: "আম", alternates: ["আমি"])
        buf.replaceCurrent(bangla: "আমি")
        XCTAssertEqual(buf.bangla, "আমি")
    }

    func testBackspace() {
        var buf = CompositionBuffer()
        buf.append(latin: "ami", bangla: "আমি")
        XCTAssertTrue(buf.backspace())
        XCTAssertFalse(buf.isEmpty)
    }

    func testCommitThenNewSegment() {
        var buf = CompositionBuffer()
        buf.append(latin: "am", bangla: "আম")
        buf.commitCurrent()
        buf.append(latin: "i", bangla: "ই")
        XCTAssertEqual(buf.segments.count, 2)
    }
}

final class SortedPrefixTreeTests: XCTestCase {
    func testInsertAndSearch() {
        let tree = SortedPrefixTree()
        tree.insert(Candidate(bangla: "আমি", score: 0.9))
        tree.insert(Candidate(bangla: "আমার", score: 0.8))
        tree.insert(Candidate(bangla: "তুমি", score: 0.7))
        // The tree keys on Swift Characters (grapheme clusters), so a prefix must
        // be cluster-aligned: "আ" matches the two আ-words but not তুমি.
        let results = tree.search(prefix: "আ", limit: 10)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.bangla, "আমি")  // higher score first
    }

    func testEmptyPrefixMiss() {
        let tree = SortedPrefixTree()
        tree.insert(Candidate(bangla: "আমি"))
        XCTAssertTrue(tree.search(prefix: "তু", limit: 10).isEmpty)
    }
}

final class EditDistanceTests: XCTestCase {
    func testIdentical() {
        XCTAssertEqual(EditDistance.damerauLevenshtein("ami", "ami"), 0)
    }
    func testTransposition() {
        // "amr" vs "arm" differ by one transposition -> distance 1
        XCTAssertEqual(EditDistance.damerauLevenshtein("amr", "arm"), 1)
    }
    func testSubstitution() {
        XCTAssertEqual(EditDistance.damerauLevenshtein("ami", "ami".replacingOccurrences(of: "i", with: "u")), 1)
    }
    func testScorer() {
        let s = EditDistanceScorer(maxThreshold: 2)
        XCTAssertEqual(s.score("ami", against: "ami"), 1.0, accuracy: 0.001)
        // A different word must score strictly lower than an identical match.
        XCTAssertLessThan(s.score("ami", against: "tumi"), s.score("ami", against: "ami"))
    }
}

final class ScoringPipelineTests: XCTestCase {
    func testRankingOrdersByScore() {
        let pipeline = ScoringPipeline(maxCandidates: 5)
        let inputs = ScoringPipeline.Inputs(
            latinQuery: "am",
            banglaPrefix: "আ",
            lexicon: [
                Candidate(bangla: "আমি", latinHint: "ami", source: .lexicon, score: 0.9),
                Candidate(bangla: "আমার", latinHint: "amar", source: .lexicon, score: 0.8),
                Candidate(bangla: "তুমি", latinHint: "tumi", source: .lexicon, score: 0.5),
            ]
        )
        let list = pipeline.rank(inputs, now: Date())
        XCTAssertEqual(list.entries.first?.bangla, "আমি")
        XCTAssertLessThanOrEqual(list.entries.count, 5)
    }

    func testDedupKeepsMax() {
        let pipeline = ScoringPipeline()
        let inputs = ScoringPipeline.Inputs(
            latinQuery: "am",
            banglaPrefix: "আ",
            lexicon: [
                Candidate(bangla: "আমি", latinHint: "ami", source: .lexicon, score: 0.5),
                Candidate(bangla: "আমি", latinHint: "ami", source: .user, score: 0.9),
            ]
        )
        let list = pipeline.rank(inputs)
        XCTAssertEqual(list.entries.count, 1)
        XCTAssertEqual(list.entries.first?.source, .user)
    }

    func testPrimaryIsTopEntry() {
        let pipeline = ScoringPipeline(maxCandidates: 3)
        let inputs = ScoringPipeline.Inputs(
            latinQuery: "am",
            banglaPrefix: "আ",
            lexicon: [Candidate(bangla: "আমি", latinHint: "ami", score: 0.9)]
        )
        let list = pipeline.rank(inputs)
        XCTAssertEqual(list.primary?.bangla, list.entries.first?.bangla)
    }
}

final class LayoutLoadingTests: XCTestCase {
    func testLoadAllLayouts() throws {
        let layouts = try LayoutLoader.loadAll(fromDirectory: layoutsDir)
        XCTAssertGreaterThanOrEqual(layouts.count, 5)
        XCTAssertTrue(layouts.contains { $0.id == "avro-phonetic" })
        XCTAssertTrue(layouts.contains { $0.id == "probhat" })
    }

    func testFixedLayoutKind() throws {
        let probhat = try LayoutLoader.load(from: layoutsDir.appendingPathComponent("probhat.json"))
        XCTAssertEqual(probhat.kind, .fixed)
        XCTAssertFalse(probhat.keymap.isEmpty)
    }
}