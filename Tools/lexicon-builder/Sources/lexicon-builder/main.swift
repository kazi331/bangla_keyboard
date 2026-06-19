import Foundation
import BanglaEngine
import BanglaStorage

/// lexicon-builder
///
/// Builds a read-only `lexicon.db` for the Bangla IME from:
///   1. Phonetic layout JSONs  -> `phoneme_map` (rule_set = layout id)
///   2. A curated seed dictionary (see SeedDictionary.swift) -> `word` / `word_fts` / `latin_fts`
///   3. An optional external wordlist (`--wordlist`) -> same tables
///
/// Usage:
///   lexicon-builder --output Resources/lexicon.db \
///                   --layouts Targets/BanglaIMEExtension/Resources/layouts \
///                   [--wordlist path/to/words.tsv]
///
/// Wordlist format: `latin<TAB>bangla[<TAB>freq]` per line; `#` lines are comments.

struct Options {
    var output = "Resources/lexicon.db"
    var layouts = "Targets/BanglaIMEExtension/Resources/layouts"
    var wordlist: String?
    var verbose = false
}

let argv = CommandLine.arguments
var opts = Options()
var i = 1
while i < argv.count {
    switch argv[i] {
    case "--output":    opts.output = argv[i+1]; i += 2
    case "--layouts":   opts.layouts = argv[i+1]; i += 2
    case "--wordlist":  opts.wordlist = argv[i+1]; i += 2
    case "-v", "--verbose": opts.verbose = true; i += 1
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        FileHandle.standardError.write("Unknown argument: \(argv[i])\n".data(using: .utf8)!)
        exit(2)
    }
}

let usage = """
lexicon-builder --output <path> --layouts <dir> [--wordlist <file>] [-v]
"""

@MainActor func log(_ s: String) { if opts.verbose { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) } }

// 1. Resolve output path.
let outputURL = URL(fileURLWithPath: opts.output)
let outputDir = outputURL.deletingLastPathComponent()
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: outputURL.path) {
    try FileManager.default.removeItem(at: outputURL)
    log("Removed existing \(outputURL.lastPathComponent)")
}

// 2. Open writable lexicon + build schema.
let pool = try ConnectionPool(path: outputURL.path, kind: .lexiconWritable)
try Migration.buildLexiconSchema(pool)
log("Created lexicon schema at \(outputURL.path)")

// 3. Phonetic layouts -> phoneme_map.
let layoutsDir = URL(fileURLWithPath: opts.layouts)
let layouts = try LayoutLoader.loadAll(fromDirectory: layoutsDir)
log("Loaded \(layouts.count) layouts from \(layoutsDir.path)")

let lexiconRepo = LexiconRepository(pool: pool)
var phonemeCount = 0
for layout in layouts where layout.kind == .phonetic {
    // Rules first (highest priority), then vowels/independent/consonant endings/specials.
    var priority = 100
    func insertMap(_ k: String, _ v: String, weight: Double) {
        guard !k.isEmpty, !v.isEmpty else { return }
        do {
            try lexiconRepo.insertPhonemeMapping(latin: k, bangla: v, ruleSet: layout.id, weight: weight, priority: priority)
            phonemeCount += 1
        } catch {
            log("phoneme_map insert failed: \(k)->\(v) (\(error))")
        }
    }
    for r in layout.rules { insertMap(r.match, r.output, weight: r.weight); priority -= 0 }
    for (k, v) in layout.vowelSigns { insertMap(k, v, weight: 1.0) }
    for (k, v) in layout.independentVowels { insertMap(k, v, weight: 0.9) }
    for (k, v) in layout.consonantEndings { insertMap(k, v, weight: 0.9) }
    for (k, v) in layout.specials { insertMap(k, v, weight: 1.0) }
}
log("Inserted \(phonemeCount) phoneme_map rows")

// 4. Seed dictionary -> word tables.
var wordCount = 0
@MainActor func insertWord(latin: String, bangla: String, freq: Double, source: String) {
    guard !latin.isEmpty, !bangla.isEmpty else { return }
    do {
        try lexiconRepo.insertWord(bangla: bangla, baseFreq: freq, isProper: false, source: source, latinHints: [latin])
        wordCount += 1
    } catch {
        log("word insert failed: \(latin)->\(bangla) (\(error))")
    }
}
for e in SeedDictionary.entries {
    insertWord(latin: e.latin, bangla: e.bangla, freq: e.freq, source: "seed")
}
log("Inserted \(wordCount) seed words")

// 5. Optional external wordlist.
if let wl = opts.wordlist {
    let url = URL(fileURLWithPath: wl)
    guard let data = try? Data(contentsOf: url) else {
        FileHandle.standardError.write("Could not read wordlist: \(wl)\n".data(using: .utf8)!)
        exit(2)
    }
    let before = wordCount
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.split(separator: "\t").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { continue }
        let freq = parts.count > 2 ? (Double(parts[2]) ?? 0.25) : 0.25
        insertWord(latin: parts[0], bangla: parts[1], freq: freq, source: "wordlist")
    }
    log("Added \(wordCount - before) words from external wordlist")
}

// 6. Finalize: VACUUM + close.
try pool.connection().exec("VACUUM;")
pool.close()

// 7. Report.
let finalCount = try LexiconRepository(pool: ConnectionPool(path: outputURL.path, kind: .lexicon)).count()
print("lexicon-builder: wrote \(outputURL.path)")
print("  words      : \(finalCount)")
print("  phoneme_map : \(phonemeCount)")
print("  layouts     : \(layouts.count)")