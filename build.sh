#!/usr/bin/env bash
#
# build.sh — Release build, packaging and DMG generation for BanglaIME.
#
# Produces:
#   build/                  intermediate + assembled .app bundles
#   dist/BanglaIME-<ver>.dmg  distributable disk image
#
# Pipeline: clean -> test -> release build -> regenerate lexicon.db ->
#           assemble BanglaIME.app + BanglaSettings.app -> ad-hoc sign ->
#           spctl assess -> DMG.
#
# Requires the full Xcode toolchain (XCTest + InputMethodKit frameworks live
# there, not in CommandLineTools). If xcode-select points at CLT, this script
# auto-overrides via DEVELOPER_DIR (no sudo needed).
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="1.0.0"
BUNDLE_ID_IME="com.banglaime.inputmethod.BanglaIME"
BUNDLE_ID_SETTINGS="com.banglaime.BanglaSettings"
MODULE_NAME="BanglaIMEExtension"

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
RELEASE_BIN=".build/release"
SKIP_TESTS="${SKIP_TESTS:-0}"

# ANSI colours (disabled if not a tty).
if [ -t 1 ]; then
    C_B="\033[1;34m"; C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_0="\033[0m"
else
    C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi
step() { printf "${C_B}▶ %s${C_0}\n" "$*"; }
ok()   { printf "${C_G}✓ %s${C_0}\n" "$*"; }
warn() { printf "${C_Y}⚠ %s${C_0}\n" "$*" >&2; }
die()  { printf "${C_R}✗ %s${C_0}\n" "$*" >&2; exit 1; }

# ── Toolchain ────────────────────────────────────────────────────────────────
# XCTest & IMK are only shipped with a full Xcode. If the active developer dir
# is CommandLineTools, point at Xcode.app instead.
ensure_developer_dir() {
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        local current
        current="$(xcode-select -p 2>/dev/null || true)"
        if [ "$current" = "/Library/Developer/CommandLineTools" ] || [ ! -f "$current/usr/bin/xctest" ]; then
            if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
                export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
            fi
        fi
    fi
    if ! xcrun --find xctest >/dev/null 2>&1; then
        die "XCTest not found. Install Xcode or run: sudo xcode-select -s /Applications/Xcode.app"
    fi
    [ -n "${DEVELOPER_DIR:-}" ] && warn "Using DEVELOPER_DIR=$DEVELOPER_DIR"
}
ensure_developer_dir

# ── Helpers ──────────────────────────────────────────────────────────────────
# Substitute Xcode-style plist placeholders in a file.
substitute_plist() {
    local src="$1" dst="$2" bid="$3"
    sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${bid}/g" \
        -e "s/\$(PRODUCT_MODULE_NAME)/${MODULE_NAME}/g" \
        "$src" > "$dst"
}

# ── Clean ────────────────────────────────────────────────────────────────────
step "Clean"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
ok "Cleaned build/ and dist/"

# ── Test ─────────────────────────────────────────────────────────────────────
if [ "$SKIP_TESTS" != "1" ]; then
    step "Run test suite"
    if swift test 2>&1 | tee "$BUILD_DIR/test.log"; then
        ok "Tests passed (see build/test.log)"
    else
        die "Tests failed (see build/test.log)"
    fi
else
    warn "SKIP_TESTS=1 — skipping test suite"
fi

# ── Release build ────────────────────────────────────────────────────────────
step "Release build (swift build -c release)"
swift build -c release 2>&1 | tee "$BUILD_DIR/release-build.log"
IME_BIN="$RELEASE_BIN/bangla-ime"
SETTINGS_BIN="$RELEASE_BIN/bangla-settings"
LEXICON_BUILDER_BIN="$RELEASE_BIN/lexicon-builder"
for b in "$IME_BIN" "$SETTINGS_BIN" "$LEXICON_BUILDER_BIN"; do
    [ -x "$b" ] || die "Missing release product: $b"
done
ok "Built bangla-ime, bangla-settings, lexicon-builder"

# ── Regenerate lexicon.db ────────────────────────────────────────────────────
step "Regenerate lexicon.db"
LAYOUTS_SRC="$ROOT/Targets/BanglaIMEExtension/Resources/layouts"
LEXICON_DB="$BUILD_DIR/lexicon.db"
"$LEXICON_BUILDER_BIN" --output "$LEXICON_DB" --layouts "$LAYOUTS_SRC" -v \
    2> "$BUILD_DIR/lexicon-builder.log" || die "lexicon-builder failed"
[ -f "$LEXICON_DB" ] || die "lexicon.db not produced"
# Mirror back to the source resource so SwiftPM .copy stays in sync.
cp "$LEXICON_DB" "$ROOT/Targets/BanglaIMEExtension/Resources/lexicon.db"
ok "Generated lexicon.db ($(stat -f%z "$LEXICON_DB") bytes)"

# ── Assemble BanglaIME.app ───────────────────────────────────────────────────
step "Assemble BanglaIME.app"
IME_APP="$BUILD_DIR/BanglaIME.app"
mkdir -p "$IME_APP/Contents/MacOS" "$IME_APP/Contents/Resources"
cp "$IME_BIN" "$IME_APP/Contents/MacOS/bangla-ime"
substitute_plist "$ROOT/Targets/BanglaIMEExtension/Info.plist" \
    "$IME_APP/Contents/Info.plist" "$BUNDLE_ID_IME"
cp -R "$LAYOUTS_SRC" "$IME_APP/Contents/Resources/layouts"
cp "$LEXICON_DB" "$IME_APP/Contents/Resources/lexicon.db"
cp "$ROOT/Targets/BanglaIMEExtension/Entitlements/BanglaIME.entitlements" \
   "$IME_APP/Contents/Resources/BanglaIME.entitlements"
chmod +x "$IME_APP/Contents/MacOS/bangla-ime"
ok "BanglaIME.app assembled"

# ── Assemble BanglaSettings.app ──────────────────────────────────────────────
step "Assemble BanglaSettings.app"
SETTINGS_APP="$BUILD_DIR/BanglaSettings.app"
mkdir -p "$SETTINGS_APP/Contents/MacOS" "$SETTINGS_APP/Contents/Resources"
cp "$SETTINGS_BIN" "$SETTINGS_APP/Contents/MacOS/bangla-settings"
substitute_plist "$ROOT/Targets/BanglaSettings/Info.plist" \
    "$SETTINGS_APP/Contents/Info.plist" "$BUNDLE_ID_SETTINGS"
cp "$ROOT/Targets/BanglaSettings/Entitlements/BanglaSettings.entitlements" \
   "$SETTINGS_APP/Contents/Resources/BanglaSettings.entitlements"
chmod +x "$SETTINGS_APP/Contents/MacOS/bangla-settings"
ok "BanglaSettings.app assembled"

# ── Ad-hoc sign ──────────────────────────────────────────────────────────────
step "Ad-hoc codesign"
codesign --force --deep --sign - \
    --entitlements "$IME_APP/Contents/Resources/BanglaIME.entitlements" \
    "$IME_APP" 2>&1 | tee -a "$BUILD_DIR/release-build.log" || warn "IME codesign warning"
codesign --force --deep --sign - \
    --entitlements "$SETTINGS_APP/Contents/Resources/BanglaSettings.entitlements" \
    "$SETTINGS_APP" 2>&1 | tee -a "$BUILD_DIR/release-build.log" || warn "Settings codesign warning"
ok "Ad-hoc signed both apps"
warn "Ad-hoc signature: Gatekeeper will report 'not signed' — see docs/INSTALL.md"

# ── Verify bundles ──────────────────────────────────────────────────────────
step "Verify bundles"
for app in "$IME_APP" "$SETTINGS_APP"; do
    if spctl --assess --type execute -vv "$app" 2>/dev/null; then
        ok "spctl assess passed: $(basename "$app")"
    else
        warn "spctl assess (expected for ad-hoc): $(basename "$app")"
    fi
    codesign --verify --verbose=1 "$app" >/dev/null 2>&1 && ok "codesign verify: $(basename "$app")" \
        || warn "codesign verify (ad-hoc): $(basename "$app")"
done
# Sanity-check the IME plist substitutions were applied (no stray $() tokens).
if grep -q '$(PRODUCT' "$IME_APP/Contents/Info.plist"; then
    die "Unresolved plist placeholders in BanglaIME.app/Contents/Info.plist"
fi
ok "Info.plist placeholders resolved"

# ── DMG ──────────────────────────────────────────────────────────────────────
step "Create DMG"
DMG="$DIST_DIR/BanglaIME-${VERSION}.dmg"
STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$STAGING"
cp -R "$IME_APP" "$STAGING/"
cp -R "$SETTINGS_APP" "$STAGING/"
# Drag-to-Applications symlink for convenience.
ln -sf /Applications "$STAGING/Applications"
hdiutil create -volname "BanglaIME $VERSION" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null 2>&1 || die "hdiutil failed"
ok "DMG: $DMG ($(stat -f%z "$DMG") bytes)"

# ── Summary ──────────────────────────────────────────────────────────────────
step "Summary"
printf "  IME app       : %s\n" "$IME_APP"
printf "  Settings app  : %s\n" "$SETTINGS_APP"
printf "  DMG           : %s\n" "$DMG"
printf "  Lexicon DB    : %s (%s bytes)\n" "$LEXICON_DB" "$(stat -f%z "$LEXICON_DB")"
ok "Build complete."