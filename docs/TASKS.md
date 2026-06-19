# Tasks — Bangla Input Method for macOS

Legend: `[ ]` Pending → `[-]` In Progress → `[x]` Complete

## M1 — Workspace skeleton
- [x] T1.1 Create `Package.swift` with BanglaEngine, BanglaStorage, BanglaXPC library products and bangla-ime, bangla-settings, lexicon-builder executable products. _Deps: —_ _Done: `swift build` exits 0._
- [x] T1.2 Create directory tree per architecture (Packages/, Targets/, Tools/, Tests/, CI/, Resources/). _Deps: —_ _Done: tree exists._

## M2 — Engine
- [x] T2.1 Models: `Candidate`, `Layout`, `CompositionState`, `Segment`. _Deps: T1.1_
- [x] T2.2 `BanglaRanges` + `Normalizer` (NFC, ZWJ/dotted-circle cleanup). _Deps: T1.1_
- [x] T2.3 Layout JSON loader + Avro-compatible rule grammar. _Deps: T2.1_
- [x] T2.4 Layout adapters: Phonetic (Avro), Probhat, Munir Optical, National Jatiya, Borno. _Deps: T2.3_
- [x] T2.5 `CompositionBuffer` with per-segment re-edit support. _Deps: T2.1_
- [x] T2.6 Longest-match phonetic resolver with alternates + independent-vowel/kar disambiguation. _Deps: T2.4, T2.5_
- [x] T2.7 `SortedPrefixTree` for in-memory fallback. _Deps: T2.1_

## M3 — Storage
- [x] T3.1 `ConnectionPool` (WAL, busy_timeout, mmap; lexicon read-only, user read-write, lexiconWritable). _Deps: T1.1_
- [x] T3.2 Schema v1/v2 (lexicon.db + user.db) with FTS5 virtual tables + external-content triggers. _Deps: T3.1_
- [x] T3.3 Migrations runner with `schema_version` + base-DDL-first ordering. _Deps: T3.2_
- [x] T3.4 `LexiconRepository` (prefix search via FTS5, phoneme_map). _Deps: T3.2_
- [x] T3.5 `UserRepository` (CRUD w/ UNIQUE upsert, history, ngram, session layout). _Deps: T3.2_
- [x] T3.6 Backup (`VACUUM INTO`) + restore. _Deps: T3.5_

## M4 — Ranking
- [x] T4.1 `LexiconScorer`, `EditDistanceScorer` (Damerau-Levenshtein). _Deps: T2.6_
- [x] T4.2 `NGramLanguageModel` (3-gram, online write). _Deps: T3.5_
- [x] T4.3 `PersonalizationBlend` (recency, freq, context, app, length penalty). _Deps: T4.1, T4.2_
- [x] T4.4 `ScoringPipeline` orchestration (dedup, sort, tie-break). _Deps: T4.3_

## M5 — Lexicon build tool
- [x] T5.1 `Tools/lexicon-builder` Swift CLI: parses Avro layout JSON + wordlist → `lexicon.db`. _Deps: T3.2, T2.3_
- [x] T5.2 Bundled wordlist seed (curated ~295 frequent tuples). _Deps: —_
- [x] T5.3 Run builder → `Resources/lexicon.db` (295 words, 237 phoneme rows, 5 layouts). _Deps: T5.1, T5.2_

## M6 — IMK bundle
- [x] T6.1 `IMKInputController` subclass (`@objc(BanglaInputController)`) with `inputText:client:` + `handle:client:`. _Deps: T2.6, T4.4_
- [x] T6.2 `CompositionSession` state machine (non-@MainActor to coexist with IMK base). _Deps: T6.1_
- [x] T6.3 XPC client to Settings app (`BanglaXPCClient`, soft-fail). _Deps: T1.1, T6.1_
- [x] T6.4 `Info.plist` with IMK keys + Bengali repertoire; `build.sh` substitutes `$(PRODUCT_*)`. _Deps: T6.1_
- [x] T6.5 Entitlements plist (sandbox off for ad-hoc local; production notes inline). _Deps: T6.4_

## M7 — Candidate UI
- [x] T7.1 `CandidatePanel` (NSPanel, floating, becomesKeyOnlyIfNeeded). _Deps: T6.1_
- [x] T7.2 `CandidateView` with keyboard nav (Up/Down/Enter/1-9). _Deps: T7.1_
- [x] T7.3 Caret positioning via `firstRect(forCharacterRange:)` + mouse fallback. _Deps: T7.1_
- [x] T7.4 Inline marked-text rendering in host via `setMarkedText`. _Deps: T6.2_

## M8 — Settings app
- [x] T8.1 SwiftUI `App` with `Settings` scene (General, Layouts, Dictionary, Learning, About) + MenuBarExtra. _Deps: T1.1_
- [x] T8.2 XPC listener embedded (`NSXPCListenerDelegate`). _Deps: T8.1_
- [x] T8.3 Dictionary import/export (TSV via NSSavePanel/NSSavePanel). _Deps: T8.1_
- [x] T8.4 Burn-history + vacuum. _Deps: T8.1_

## M9 — Tests
- [x] T9.1 Engine: Avro parity regression tests (ami/tumi/amar/bangla/bangladesh/kichu, clusters, digits, danda). _Deps: T2.6_
- [x] T9.2 Engine: Normalizer tests (NFC, dotted-circle, ZWJ, canonical detection). _Deps: T2.2_
- [x] T9.3 Storage: migration + FTS trigger + idempotency tests. _Deps: T3.3_
- [x] T9.4 Storage: FTS prefix performance test (<20ms/lookup over 2k rows). _Deps: T3.4_
- [x] T9.5 Ranking: deterministic ordering with seeded user.db + dedup. _Deps: T4.4_
- [x] T9.6 End-to-end: keystroke → candidate list → commit → learned word (in-process). _Deps: T6.1, T4.4_

## M10 — Build & packaging
- [x] T10.1 `build.sh`: clean + release build + test. _Deps: M9_
- [x] T10.2 `build.sh`: assemble `BanglaIME.app` + `BanglaSettings.app` (plist substitution, resources). _Deps: T10.1_
- [x] T10.3 `build.sh`: ad-hoc sign + `spctl --assess` + `codesign --verify` (best effort). _Deps: T10.2_
- [x] T10.4 `build.sh`: build DMG via `hdiutil` (UDZO, Applications symlink). _Deps: T10.3_

## M11 — Final report
- [x] T11.1 `docs/FINAL_REPORT.md`. _Deps: M10_
- [x] T11.2 `docs/INSTALL.md`. _Deps: M10_