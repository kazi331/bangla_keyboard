# BanglaIME — Installation Guide

A phonetic + fixed-layout Bangla input method for macOS 13+.

> **Build status:** This release is **ad-hoc signed** (no Developer ID). macOS
> Gatekeeper will warn that the app is "not signed" / "from an unidentified
> developer." That is expected — see [Ad-hoc / unsigned install](#ad-hoc--unsigned-install).
> For wide distribution you must replace the ad-hoc signature with a notarized
> Developer ID build (see [Production signing](#production-signing-notarization)).

---

## 1. Requirements

- macOS 13.0 (Ventura) or newer
- **A full Xcode installation** (not just Command Line Tools). The IME links
  `InputMethodKit`/`AppKit` and the test target needs `XCTest`, both shipped
  only with Xcode. If `xcode-select -p` reports `/Library/Developer/CommandLineTools`,
  either run `sudo xcode-select -s /Applications/Xcode.app` or let `build.sh`
  auto-override via `DEVELOPER_DIR` (it does this automatically).

## 2. Build from source

```sh
git clone <repo> bangla_keyboard
cd bangla_keyboard
./build.sh
```

`build.sh` runs the full pipeline: clean → test → release build → regenerate
`lexicon.db` → assemble `BanglaIME.app` + `BanglaSettings.app` → ad-hoc sign →
verify → DMG.

To skip the test step (faster rebuilds after first verification):

```sh
SKIP_TESTS=1 ./build.sh
```

### Artifacts

| Path | What |
|------|------|
| `build/BanglaIME.app` | The input method bundle |
| `build/BanglaSettings.app` | The settings / menu-bar app |
| `dist/BanglaIME-1.0.0.dmg` | Distributable disk image (both apps + Applications symlink) |
| `build/lexicon.db` | Regenerated read-only lexicon (also mirrored to `Targets/BanglaIMEExtension/Resources/lexicon.db`) |
| `build/test.log`, `build/release-build.log` | Build/test logs |

## 3. Install the input method

The standard macOS location for user-installed input methods is
`~/Library/Input Methods/`.

### From the DMG

1. Open `dist/BanglaIME-1.0.0.dmg`.
2. Drag **BanglaIME.app** into the **Applications** folder (or directly into
   `~/Library/Input Methods/`).
3. Move the app into place:
   ```sh
   mkdir -p ~/Library/Input\ Methods
   mv /Applications/BanglaIME.app ~/Library/Input\ Methods/
   ```
4. **Log out and back in** (or restart). macOS only scans
   `~/Library/Input Methods` at login.
5. Open **System Settings → Keyboard → Input Sources → Edit… → +**,
   search **Bangla**, and add **BanglaIME**.
6. Select it from the menu-bar input menu (or ⇧⌃Space) and type.

### From the build directory directly

```sh
mkdir -p ~/Library/Input\ Methods
cp -R build/BanglaIME.app ~/Library/Input\ Methods/
# Optional: install the settings app
cp -R build/BanglaSettings.app ~/Applications/
```
Then log out/in and add the input source as above.

## 4. Install the Settings app (optional)

The Settings app lives in the menu bar and manages layouts, the user
dictionary, learning history, and database maintenance.

```sh
cp -R build/BanglaSettings.app ~/Applications/
open ~/Applications/BanglaSettings.app
```

> **XPC note:** Cross-process XPC between the IME and the Settings app
> (active-layout sync, burn-history, vacuum) requires the Settings app to
> register its mach service name with `launchd` and a properly signed, sandboxed
> build. In this ad-hoc local build those calls fail soft (return `nil`/`false`)
> rather than blocking input — the IME still reads its active-layout preference
> directly from the shared `UserDefaults` suite. See
> [Known limitations](#known-limitations).

## 5. Verify

```sh
# Bundle is well-formed and signed (ad-hoc):
codesign --verify --verbose=1 build/BanglaIME.app

# Plist resolved (no leftover $(...) placeholders):
plutil -p build/BanglaIME.app/Contents/Info.plist | grep -E 'BundleIdentifier|InputMethodConnectionName'

# Lexicon + layouts present:
ls build/BanglaIME.app/Contents/Resources/
```

## 6. Ad-hoc / unsigned install

Because the bundle is ad-hoc signed, the first launch may be blocked by
Gatekeeper. To allow it:

- **System Settings → Privacy & Security** → scroll to the "BanglaIME was
  blocked" notice → click **Open Anyway**; **or**
- Right-click the app → **Open** → confirm; **or**
- Remove the quarantine attribute before copying into place:
  ```sh
  xattr -dr com.apple.quarantine build/BanglaIME.app
  xattr -dr com.apple.quarantine build/BanglaSettings.app
  ```

`spctl --assess` will report the bundle as "not signed" — this is expected for
ad-hoc signatures and does not prevent local use.

## 7. Production signing / notarization

For distribution to other users, replace the ad-hoc signature with a notarized
Developer ID build:

1. Edit `Targets/BanglaIMEExtension/Entitlements/BanglaIME.entitlements` (and the
   Settings equivalent): set `com.apple.security.app-sandbox = true`, add your App
   Group, and add the `temporary-exception.mach-register.global-name` for the
   input-method connection name (see the inline comment in the entitlements file).
2. Sign with your Developer ID:
   ```sh
   codesign --force --deep --options runtime \
     --entitlements Targets/BanglaIMEExtension/Entitlements/BanglaIME.entitlements \
     --sign "Developer ID Application: Your Name (TEAMID)" build/BanglaIME.app
   ```
3. Notarize (`xcrun notarytool submit ... --wait`) then staple
   (`xcrun stapler staple build/BanglaIME.app`).
4. Rebuild the DMG from the notarized apps.

## 8. Uninstall

```sh
rm -rf ~/Library/Input\ Methods/BanglaIME.app
rm -rf ~/Applications/BanglaSettings.app
rm -rf ~/Library/Application\ Support/BanglaIME      # user.db + learning data
rm -rf ~/Library/Containers/com.banglaime.* 2>/dev/null
defaults delete com.banglaime.inputmethod.BanglaIME 2>/dev/null
```
Log out/in, then remove the input source from System Settings → Keyboard.

## Known limitations

- **Seed lexicon only.** The bundled `lexicon.db` ships ~295 curated words (not a
  full 20k dictionary). The ranking pipeline, FTS5 prefix search, edit-distance
  fallback, and personalization are all production-quality and will rank a
  larger lexicon with no code changes — grow it via `lexicon-builder --wordlist`
  or the Settings app's import.
- **Inherent-vowel grammar is partial.** The phonetic resolver handles
  independent vowels vs. vowel-signs (kars) based on the preceding consonant,
  consonant clusters, digits, and danda, but does not yet suppress the implicit
  "o" vowel in all contexts (e.g. `kemon` → `কেমোন` rather than `কেমন`). This is
  tracked as future grammar work; the architecture (longest-match trie with
  context tracking) is designed to absorb it.
- **XPC between IME and Settings** requires launchd registration + proper
  signing for full operation; in ad-hoc builds the calls fail soft.
- **Swift 5 language mode.** The package builds in Swift 5 mode
  (`swift-tools-version: 5.9`) because `IMKInputController`'s Objective-C base
  class is not `@MainActor`-annotated, which makes strict Swift 6 concurrency
  impractical for the IMK subclass. The engine and storage still use actors and
  `Sendable` types; they are simply not strictly checked at compile time.
- **No git history shipping** in this deliverable (the working tree is the source
  of truth).