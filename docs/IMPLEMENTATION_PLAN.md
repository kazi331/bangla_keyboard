# Implementation Plan  Bangla Input Method for macOS

Source of truth: architecture document (Principal macOS Engineer design).
Toolchain baseline: Swift 6.3.2, macOS 26.5, Xcode command-line tools, system `libsqlite3` with FTS5.

## 1. Strategy

Two Xcode-free SwiftPM packages plus two executable products, assembled into
`.app` bundles by `build.sh`. This avoids hand-maintaining `.xcodeproj` files
and keeps the build fully scriptable and CI-friendly.

- **BanglaEngine** (library): transliteration, ranking, models. Pure Swift, no AppKit.
- **BanglaStorage** (library): SQLite + FTS5 access via system `libsqlite3`.
- **BanglaXPC** (library): `@objc` XPC protocol + DTOs.
- **bangla-ime** (executable): IMK host process (`IMKInputController` subclass), loads engine + storage + candidate UI.
- **bangla-settings** (executable): SwiftUI Settings app + embedded XPC listener.

Bundling:
- `BanglaIME.app` -> `~/Library/Input Methods/` (user install).
- `BanglaSettings.app` -> `/Applications/BanglaIME/` (DMG root with symlink to `/Applications`).

## 2. Milestones

| M# | Milestone | Acceptance Criteria |
|----|-----------|---------------------|
| M1 | Workspace + package skeleton compiles | `swift build` succeeds with stub targets |
| M2 | Engine: layouts + phonetic resolver | Unit tests pass for Avro phonetic parity |
| M3 | Storage: schema + migrations + FTS5 | Migration tests pass; FTS prefix search works |
| M4 | Ranking pipeline | Ranking tests pass against seeded user.db |
| M5 | Lexicon DB builder | `lexicon.db` generated with >=20k headwords, mmap-able |
| M6 | IMK bundle (BanglaIME.app) | Bundle launches, recognized by `imklaunchagent`, accepts keystrokes |
| M7 | Candidate UI (NSPanel + SwiftUI) | Window positions near caret, shows ranked candidates, accepts selection |
| M8 | Settings app | SwiftUI app builds, reads/writes shared prefs via XPC |
| M9 | Tests green | `swift test` all pass |
| M10 | Build + packaging | `build.sh` produces both `.app`s and a stapled-able DMG |
| M11 | Final report | `docs/FINAL_REPORT.md` documents status and install steps |

## 3. Dependencies (inter-task)

```
M1 -+-> M2 -+
    +-> M3 -+-> M4 -> M5 -+
                          +-> M6 -> M7 -> M9 -> M10 -> M11
                          +-> M8 ---------------------^
```

## 4. Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| IMK + Swift 6 strict concurrency conflicts | High | Mark controller `@MainActor`; engine is `actor`; all hops explicit. Use `@objc` bridging where IMK requires. |
| FTS5 custom Bengali tokenizer requires C extension signing | Medium | Use built-in `unicode61` tokenizer with character-class config; defer custom tokenizer. |
| Notarization without Developer ID | Certain (this environment) | Build & sign ad-hoc; document notarization steps for production. DMG still generated and verified with `spctl --assess` (will note "ad-hoc"). |
| Candidate window positioning across Electron apps | High | Implement NSTextInputClient rect + AX fallback + mouse-loc fallback. |
| IMK bundle not recognized post-install | Medium | Provide `killall imklaunchagent` step in install docs; verify with `TISCreateInputSourceList`. |
| SwiftPM executable products cannot directly produce `.app` | High | Use `build.sh` post-build assembly step from executable + Info.plist + resources. |

## 5. Acceptance Criteria (Project-Level)

1. `swift build -c release` exits 0.
2. `swift test` exits 0 with >0 tests.
3. `build.sh` produces `build/BanglaIME.app` and `build/BanglaSettings.app`.
4. `build.sh` produces `dist/BanglaIME-<ver>.dmg`.
5. `spctl --assess` against the DMG either passes (signed) or reports ad-hoc signature (documented).
6. `docs/FINAL_REPORT.md` exists with install instructions.