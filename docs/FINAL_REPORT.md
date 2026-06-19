# BanglaIME — Final Verification Report

**Project:** Bangla Input Method for macOS
**Release:** 1.0.0
**Date:** 2026-06-20
**Engineer:** Autonomous delivery (single-engineer pipeline)
**Platform target:** macOS 13.0+ (arm64)

---

## 1. Executive summary

A complete, production-structured macOS Bangla input method was delivered from
architecture through a distributable DMG. The package is a SwiftPM workspace
with four libraries (BanglaEngine, BanglaStorage, BanglaXPC, BanglaCandidateUI),
three executables (bangla-ime, bangla-settings, lexicon-builder), and three test
targets. All eight success criteria are met.

The product composes Bangla text from latin keystrokes using a longest-match
phonetic resolver (Avro-compatible) with independent-vowel/vowel-sign
disambiguation, ranks candidates through a lexicon + edit-distance +
personalization pipeline backed by SQLite FTS5, and renders an inline candidate
panel via InputMethodKit. A separate SwiftUI Settings app manages layouts, the
user dictionary, learning history, and database maintenance.

## 2. Success criteria — all met

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Application builds successfully | ✅ Pass | `swift build -c release` clean, 0 warnings |
| 2 | All tests pass | ✅ Pass | 46 tests, 0 failures |
| 3 | Input Method bundle generated | ✅ Pass | `build/BanglaIME.app` (764K) |
| 4 | Settings application builds | ✅ Pass | `build/BanglaSettings.app` (708K) |
| 5 | Packaging succeeds | ✅ Pass | `build.sh` exits 0 |
| 6 | DMG generated | ✅ Pass | `dist/BanglaIME-1.0.0.dmg` (671K) |
| 7 | Installation documented | ✅ Pass | `docs/INSTALL.md` |
| 8 | Final verification report produced | ✅ Pass | this document |

## 3. Build status

```
▶ Clean → Test → Release build → lexicon.db → assemble → sign → verify → DMG
✓ Tests passed (46/46, 0 failures, 0.698s)
✓ Built bangla-ime, bangla-settings, lexicon-builder (0 warnings)
✓ Generated lexicon.db (114688 bytes; 295 words, 237 phoneme rows)
✓ BanglaIME.app assembled + ad-hoc signed + codesign verified
✓ BanglaSettings.app assembled + ad-hoc signed + codesign verified
✓ Info.plist placeholders resolved (no stray $(PRODUCT…))
✓ DMG: dist/BanglaIME-1.0.0.dmg (687172 bytes)
✓ Build complete.
```

Toolchain note: XCTest and InputMethodKit ship only with a full Xcode, not
Command Line Tools. `build.sh` auto-redirects to `DEVELOPER_DIR=/Applications/
Xcode.app/Contents/Developer` when `xcode-select -p` points at CLT — no sudo
required.

## 4. Test status

**46 tests, 0 failures (0.698s).** Three suites across 3634 lines of Swift:

| Suite | Tests | Coverage |
|-------|-------|----------|
| `BanglaEngineTests` | Resolver, Normalizer, CompositionBuffer, SortedPrefixTree, EditDistance, ScoringPipeline, LayoutLoading | Avro parity (ami→আমি, tumi→তুমি, amar→আমার, bangla→বাংলা, bangladesh→বাংলাদেশ, kichu→কিছু), clusters (kSh→ক্ষ, pr→প্র, tr→ত্র), digits/danda, NFC + ZWJ + dotted-circle normalization, dedup + deterministic ranking, fixed/phonetic layout loading |
| `BanglaStorageTests` | ConnectionPool, Migration, LexiconRepository, UserRepository, Backup, FTSPerformance | read-only rejection, migration idempotency + FTS triggers, prefix search, UNIQUE upsert, ngram suggestions, commit logging, burn-history, `VACUUM INTO` backup, prefix-search latency < 20ms over 2k rows |
| `BanglaIMEExtensionTests` | IMEEngineTransliteration, IMEEngineRanking, KeystrokeToEndToEnd | engine transliteration, fixed-mapping, rank determinism, end-to-end keystroke→candidate→commit→learned-word |

Two real bugs were found and fixed by the test suite:
1. **Migration ordering** — `migrate()` created FTS triggers referencing
   `user_word` before the table existed (only `userDDL[0]` was applied). Fixed to
   apply all base DDL first, then version-gated triggers.
2. **Missing UNIQUE constraint** — `user_word` lacked `UNIQUE` on `bangla`, so
   `ON CONFLICT(bangla) DO UPDATE` (the upsert used by learning) failed. Fixed by
   adding `UNIQUE` to the column.

## 5. Generated artifacts

```
build/BanglaIME.app/Contents/
    Info.plist                 (placeholders resolved: com.banglaime.inputmethod.BanglaIME)
    MacOS/bangla-ime           (arm64 Mach-O executable)
    Resources/lexicon.db       (295 words, FTS5)
    Resources/layouts/         (avro-phonetic, borno, munir-optical, national-jatiya, probhat)
    Resources/BanglaIME.entitlements
    _CodeSignature/CodeResources

build/BanglaSettings.app/Contents/
    Info.plist                 (com.banglaime.BanglaSettings, LSUIElement)
    MacOS/bangla-settings
    Resources/BanglaSettings.entitlements
    _CodeSignature/CodeResources

dist/BanglaIME-1.0.0.dmg      (UDZO, both apps + /Applications symlink)
build/lexicon.db              (regenerated, mirrored to source tree)
build/test.log, build/release-build.log
```

## 6. Architecture

```
Packages/
  BanglaEngine/   Models, Transliteration (PhoneticResolver, Normalizer,
                  CompositionBuffer), Ranking (Scorers, NGram, Blend, Pipeline),
                  Support (SortedPrefixTree)
  BanglaStorage/  ConnectionPool (lexicon/lexiconWritable/user kinds),
                  Schema (Migrations, SQLiteConnection, FTS5), Repositories
                  (Lexicon, User, Session), Search (Prefix, Phonetic)
  BanglaXPC/      Protocol, SharedPaths/SharedDefaults
Targets/
  BanglaIMEExtension/  IMKInputController, IMEBootstrap, IMEEngine (actor),
                       CompositionSession, BanglaXPCClient, main + Info.plist
  BanglaCandidateUI/   CandidatePanel + CandidateView
  BanglaSettings/      SwiftUI App, XPC listener/service, panes, model
Tools/lexicon-builder/  CLI: layouts + seed dict → lexicon.db
Tests/                 BanglaEngineTests, BanglaStorageTests, BanglaIMEExtensionTests
build.sh               clean→test→build→assemble→sign→verify→DMG
```

Key design decisions:
- **Sync hot path, async ranking.** `inputText` runs fully synchronous via
  `PhoneticResolver` (no actor hop) so typing never blocks the main thread;
  candidate ranking fires as a detached `Task` against the `IMEEngine` actor and
  applies to the panel on `MainActor` when it lands.
- **Swift 5 language mode** (`swift-tools-version: 5.9`). `IMKInputController`'s
  Objective-C base class isn't `@MainActor`-annotated, making strict Swift 6
  concurrency impractical for the subclass. Engine/storage still use actors +
  `Sendable`; they just aren't strictly checked at compile time.
- **Two SQLite databases.** Read-only `lexicon.db` (mmap, `query_only`) for the
  bundled dictionary; read-write `user.db` (WAL) for learning/history/ngrams.
- **FTS5 external-content** sync via insert/delete/update triggers on
  `user_word`, keeping the user-word FTS index current for prefix queries.

## 7. Remaining limitations

1. **Seed lexicon (~295 words).** The ranking pipeline, FTS5 prefix search,
   edit-distance fallback, and personalization are production-quality and will
   rank a larger lexicon with no code changes. Grow it via
   `lexicon-builder --wordlist <file>` (format: `latin<TAB>bangla[<TAB>freq]`)
   or the Settings app's dictionary import.
2. **Inherent-vowel grammar is partial.** Independent vowels vs. vowel-signs
   are disambiguated by the preceding consonant, and consonant clusters,
   digits, and danda work. Full inherent-"o" suppression (e.g. `kemon` →
   `কেমন`, not `কেমোন`) is future grammar work; the resolver's context-tracking
   trie is designed to absorb it.
3. **IME↔Settings XPC** requires `launchd` mach-service registration + proper
   signing/sandbox for full operation. In this ad-hoc local build those calls
   fail soft (return `nil`/`false`) and the IME reads its active-layout
   preference directly from the shared `UserDefaults` suite. Documented in
   `docs/INSTALL.md` §Production signing.
4. **Ad-hoc signature.** `spctl --assess` reports "not signed" (expected for
   ad-hoc). `codesign --verify` passes. For distribution, notarize with a
   Developer ID (steps in `docs/INSTALL.md` §7).
5. **No icon asset.** `Info.plist` references `main.tiff` for the IMK icon which
   is not bundled; macOS falls back to the default input-method glyph. Harmless.

## 8. How to reproduce

```sh
git clone <repo> bangla_keyboard && cd bangla_keyboard
./build.sh                      # full pipeline incl. tests → dist/BanglaIME-1.0.0.dmg
SKIP_TESTS=1 ./build.sh         # faster rebuild after first verification
swift test                      # tests only (set DEVELOPER_DIR to Xcode if needed)
```

Install: see `docs/INSTALL.md`. In short — copy `BanglaIME.app` into
`~/Library/Input Methods/`, log out/in, add the source in System Settings →
Keyboard → Input Sources, and type.