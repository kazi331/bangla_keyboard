#!/usr/bin/env bash
#
# build.sh — Release build, packaging, install and DMG generation for BanglaIME.
#
# Each layout ships as its own .app bundle with a distinct bundle identifier, so
# every layout registers as a separate input source in:
#   System Settings > Keyboard > Input Sources (the "+" list).
# The in-app "Layouts" picker is gone — switching is done from the system menu.
#
# Produces:
#   build/<LayoutName>.app    one IME bundle per layout
#   build/BanglaSettings.app   the Settings app
#   dist/BanglaIME-<ver>.dmg   distributable disk image (optional)
#
# Pipeline: clean -> test -> release build -> regenerate lexicon.db ->
#           assemble one IME.app per layout + BanglaSettings.app -> ad-hoc sign ->
#           spctl assess -> (optional) install to ~/Library/Input Methods -> DMG.
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="1.0.0"
BUNDLE_ID_PREFIX="com.banglaime.inputmethod.BanglaIME"
BUNDLE_ID_SETTINGS="com.banglaime.BanglaSettings"
MODULE_NAME="BanglaIMEExtension"

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
RELEASE_BIN=".build/release"
SKIP_TESTS="${SKIP_TESTS:-0}"
DO_INSTALL="${DO_INSTALL:-0}"

# One entry per shipped layout: <layoutId>|<short bundle/display name>
LAYOUTS=(
  "avro-phonetic|Avro Phonetic"
  "borno|Borno Phonetic"
  "probhat|Probhat"
  "munir-optical|Munir Optical"
  "national-jatiya|National Jatiya"
)

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
# Substitute Xcode-style + per-layout plist placeholders in a file.
substitute_plist() {
    local src="$1" dst="$2" bid="$3" layout_id="$4" display="$5"
    sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${bid}/g" \
        -e "s/\$(PRODUCT_MODULE_NAME)/${MODULE_NAME}/g" \
        -e "s/__LAYOUT_ID__/${layout_id}/g" \
        -e "s/__DISPLAY_NAME__/${display}/g" \
        -e "s/__BUNDLE_NAME__/${display}/g" \
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
cp "$LEXICON_DB" "$ROOT/Targets/BanglaIMEExtension/Resources/lexicon.db"
ok "Generated lexicon.db ($(stat -f%z "$LEXICON_DB") bytes)"

ENTITLEMENTS_IME="$ROOT/Targets/BanglaIMEExtension/Entitlements/BanglaIME.entitlements"
ENTITLEMENTS_SETTINGS="$ROOT/Targets/BanglaSettings/Entitlements/BanglaSettings.entitlements"

# ── Assemble one IME app per layout ───────────────────────────────────────────
step "Assemble IME apps (one per layout)"
IME_APPS=()
for entry in "${LAYOUTS[@]}"; do
    layout_id="${entry%%|*}"
    display="${entry##*|}"
    bid="${BUNDLE_ID_PREFIX}.${layout_id}"
    # Sanitize the display name into a filesystem-safe .app name.
    app_name="BanglaIME - ${display}"
    app_safe="$(printf '%s' "$app_name" | tr -d '/:' )"
    APP="$BUILD_DIR/${app_safe}.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$IME_BIN" "$APP/Contents/MacOS/bangla-ime"
    substitute_plist "$ROOT/Targets/BanglaIMEExtension/Info.plist" \
        "$APP/Contents/Info.plist" "$bid" "$layout_id" "$app_name"
    cp -R "$LAYOUTS_SRC" "$APP/Contents/Resources/layouts"
    cp "$LEXICON_DB" "$APP/Contents/Resources/lexicon.db"
    cp "$ENTITLEMENTS_IME" "$APP/Contents/Resources/BanglaIME.entitlements"
    chmod +x "$APP/Contents/MacOS/bangla-ime"
    # Sanity-check substitutions resolved.
    if grep -qE '\$(PRODUCT|__)' "$APP/Contents/Info.plist"; then
        die "Unresolved plist placeholders in $APP/Contents/Info.plist"
    fi
    IME_APPS+=("$APP")
    ok "Assembled ${app_safe}.app  (layout=${layout_id}, bid=${bid})"
done

# ── Assemble BanglaSettings.app ──────────────────────────────────────────────
step "Assemble BanglaSettings.app"
SETTINGS_APP="$BUILD_DIR/BanglaSettings.app"
mkdir -p "$SETTINGS_APP/Contents/MacOS" "$SETTINGS_APP/Contents/Resources"
cp "$SETTINGS_BIN" "$SETTINGS_APP/Contents/MacOS/bangla-settings"
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID_SETTINGS}/g" \
    "$ROOT/Targets/BanglaSettings/Info.plist" > "$SETTINGS_APP/Contents/Info.plist"
cp "$ENTITLEMENTS_SETTINGS" "$SETTINGS_APP/Contents/Resources/BanglaSettings.entitlements"
chmod +x "$SETTINGS_APP/Contents/MacOS/bangla-settings"
ok "BanglaSettings.app assembled"

# ── Ad-hoc sign ──────────────────────────────────────────────────────────────
step "Ad-hoc codesign"
for APP in "${IME_APPS[@]}" "$SETTINGS_APP"; do
    ent=""
    for cand in "$APP/Contents/Resources/BanglaIME.entitlements" "$APP/Contents/Resources/BanglaSettings.entitlements"; do
        [ -f "$cand" ] && ent="$cand" && break
    done
    if [ -n "$ent" ]; then
        codesign --force --deep --sign - --entitlements "$ent" \
            "$APP" 2>&1 | tee -a "$BUILD_DIR/release-build.log" \
            || warn "codesign warning: $(basename "$APP")"
    else
        codesign --force --deep --sign - \
            "$APP" 2>&1 | tee -a "$BUILD_DIR/release-build.log" \
            || warn "codesign warning: $(basename "$APP")"
    fi
done
ok "Ad-hoc signed all apps"
warn "Ad-hoc signature: Gatekeeper will report 'not signed' — see docs/INSTALL.md"

# ── Verify bundles ────────────────────────────────────────────────────────────
step "Verify bundles"
for APP in "${IME_APPS[@]}" "$SETTINGS_APP"; do
    if spctl --assess --type execute -vv "$APP" 2>/dev/null; then
        ok "spctl assess passed: $(basename "$APP")"
    else
        warn "spctl assess (expected for ad-hoc): $(basename "$APP")"
    fi
    codesign --verify --verbose=1 "$APP" >/dev/null 2>&1 && ok "codesign verify: $(basename "$APP")" \
        || warn "codesign verify (ad-hoc): $(basename "$APP")"
done
ok "Bundles verified"

# ── Install to ~/Library/Input Methods ────────────────────────────────────────
if [ "$DO_INSTALL" = "1" ]; then
    step "Install to ~/Library/Input Methods"
    DEST="$HOME/Library/Input Methods"
    mkdir -p "$DEST"
    # Remove any previously-installed BanglaIME bundles (old single-app or per-layout).
    rm -rf "$DEST/BanglaIME.app"
    for f in "$DEST"/BanglaIME\ -\ *.app; do rm -rf "$f"; done
    for APP in "${IME_APPS[@]}"; do
        cp -R "$APP" "$DEST/"
        ok "Installed $(basename "$APP")"
    done
    cp -R "$SETTINGS_APP" "$DEST/"
    ok "Installed BanglaSettings.app"
    # Stop any running instance so the freshly installed bundles are reloaded.
    pkill -x bangla-ime 2>/dev/null || true
    pkill -x bangla-settings 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$DEST"/*.app 2>/dev/null || true
    ok "Install complete. Enable the layouts in System Settings > Keyboard > Input Sources."
fi

# ── DMG ──────────────────────────────────────────────────────────────────────
if [ "${BUILD_DMG:-1}" = "1" ]; then
    step "Create DMG"
    DMG="$DIST_DIR/BanglaIME-${VERSION}.dmg"
    STAGING="$BUILD_DIR/dmg-staging"
    mkdir -p "$STAGING"
    for APP in "${IME_APPS[@]}" "$SETTINGS_APP"; do
        cp -R "$APP" "$STAGING/"
    done
    ln -sf /Applications "$STAGING/Applications"
    hdiutil create -volname "BanglaIME $VERSION" -srcfolder "$STAGING" \
        -ov -format UDZO "$DMG" >/dev/null 2>&1 || die "hdiutil failed"
    ok "DMG: $DMG ($(stat -f%z "$DMG") bytes)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
step "Summary"
for APP in "${IME_APPS[@]}"; do
    printf "  IME app        : %s\n" "$APP"
done
printf "  Settings app   : %s\n" "$SETTINGS_APP"
[ -f "$DIST_DIR/BanglaIME-${VERSION}.dmg" ] && printf "  DMG            : %s\n" "$DIST_DIR/BanglaIME-${VERSION}.dmg"
printf "  Lexicon DB     : %s (%s bytes)\n" "$LEXICON_DB" "$(stat -f%z "$LEXICON_DB")"
ok "Build complete."
