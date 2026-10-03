#!/bin/bash
# build-app.sh — builds, tests, assembles, signs, verifies and packages mac/dist/AA.app (owner: W-SHELL).
# Spec: 03 SHELL-180…191 (bundle, universal slices, Info.plist, camera text, icon + resources, .aaz document type,
#       entitlements / not sandboxed, ad-hoc signing, Gatekeeper procedure, translocation, distribution containers),
#       SHELL-200…203 (compile gate incl. "no warning: lines", test gate, this script, bundle verification),
#       BD.3.9 (the 15 steps), BD.3.10 (icon), BD.3.11 (version stamping), BD.4.1–BD.4.6, BD.7.3 (resource
#       checksums), BD.7.4 (bundle assertions); DECISIONS 01 Q-7 (not sandboxed, ad-hoc signed); ARCHITECTURE-BRIEF
#       "Toolchain & packaging". Writes only under mac/.build, mac/dist and a temp folder; reads the original sources
#       only to compare checksums (rule zero).
set -euo pipefail

MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="build-app.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/build-app.sh [--help]

Builds mac/dist/AA.app (universal arm64 + x86_64, macOS 26, hardened runtime, ad-hoc signed, not sandboxed),
verifies it, and writes mac/dist/AA-<version>-<build>-macOS.zip and mac/dist/SHA256SUMS.

Environment (all optional):
  CONFIGURATION      release (default) | debug
  ARCHS              "arm64 x86_64" (default)
  VERSION            CFBundleShortVersionString (default: contents of mac/VERSION, else 1.0.0)
  BUILD_NUMBER       CFBundleVersion (default: git rev-list --count HEAD, else 1)
  SIGN_IDENTITY      "-" = ad-hoc (default), or a named code-signing identity
  NOTARY_PROFILE     notarytool keychain profile (Developer ID identities only)
  AA_BAKE_DATA_DIR   bake LSEnvironment AA_DATA_DIR=<abs path> into Info.plist (discouraged, SHELL-195)
  PACKAGE            zip (default) | dmg (zip + dmg) | none
  PORTABLE_LAUNCHER  1 = add "AA (portable).command" to the package (default 0)
  SKIP_TESTS         1 = skip `swift test` (default 0)
  STRIP              1 = strip symbols (default 1); the dSYM is kept in dist/
  AA_MAX_APP_MB      size tripwire in MB (default 60)
  AA_JOBS            parallel build jobs (default 3 — the build Mac is shared)

Exit status: 0 = success, 1 = a step failed (stderr names it), 2 = usage error.

First launch of an ad-hoc signed copy that arrived through a browser, Mail, Messages or AirDrop (macOS 15+):
  1. Move AA.app to Applications (or any permanent folder) with Finder BEFORE opening it (avoids App Translocation).
  2. Double-click it. macOS says it could not verify AA and offers only Done / Move to Trash. Choose Done.
  3. Open System Settings ▸ Privacy & Security, scroll to Security, find the line saying AA was blocked, click
     Open Anyway and authenticate.
  4. Double-click AA again and confirm Open Anyway once more. From then on it opens normally.
  Terminal alternative, after moving the app:  xattr -dr com.apple.quarantine /Applications/AA.app
EOF
}

case "${1:-}" in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$SELF: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------------------------------------------
# Inputs (BD.3.9)
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
if [ -z "${VERSION:-}" ]; then
    if [ -s "$MAC_DIR/VERSION" ]; then VERSION="$(tr -d ' \t\r\n' < "$MAC_DIR/VERSION")"; else VERSION="1.0.0"; fi
fi
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="$(git -C "$MAC_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
PACKAGE="${PACKAGE:-zip}"
PORTABLE_LAUNCHER="${PORTABLE_LAUNCHER:-0}"
SKIP_TESTS="${SKIP_TESTS:-0}"
STRIP="${STRIP:-1}"
AA_MAX_APP_MB="${AA_MAX_APP_MB:-60}"
AA_JOBS="${AA_JOBS:-3}"

case "$CONFIGURATION" in release|debug) ;; *) echo "$SELF: CONFIGURATION must be release or debug" >&2; exit 2 ;; esac
case "$PACKAGE" in zip|dmg|none) ;; *) echo "$SELF: PACKAGE must be zip, dmg or none" >&2; exit 2 ;; esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$SELF: VERSION must be MAJOR.MINOR.PATCH (got $VERSION)" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "$SELF: BUILD_NUMBER must be a positive integer" >&2; exit 2; }

DIST="$MAC_DIR/dist"
T="$(mktemp -d "${TMPDIR:-/tmp}/aa-build-app.XXXXXX")"
STEP=0
STEP_NAME="start"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
on_error() { echo "$SELF: step $STEP ($STEP_NAME) failed" >&2; exit 1; }
trap on_error ERR

step() { STEP="$1"; STEP_NAME="$2"; echo "==> [$STEP] $STEP_NAME"; }
fail() { echo "  ✗ $*" >&2; echo "$SELF: step $STEP ($STEP_NAME) failed" >&2; exit 1; }
ok() { echo "  ✓ $*"; }

APP="$T/AA.app"
CONTENTS="$APP/Contents"

# ---------------------------------------------------------------------------------------------------------------
step 1 "preconditions"
[ "$(uname -s)" = "Darwin" ] || fail "not a Mac"
xcrun --find swift >/dev/null || fail "swift not found (install Xcode)"
DEV_DIR="$(xcode-select -p)"
case "$DEV_DIR" in *.app/Contents/Developer) ;; *) fail "select a full Xcode (xcode-select -p = $DEV_DIR)" ;; esac
for tool in iconutil sips codesign lipo plutil ditto shasum xattr; do
    command -v "$tool" >/dev/null || fail "missing tool: $tool"
done
for tool in vtool otool dsymutil strip; do
    xcrun --find "$tool" >/dev/null || fail "missing tool: xcrun $tool"
done
ok "Xcode at $DEV_DIR; version $VERSION ($BUILD_NUMBER); archs: $ARCHS"

# ---------------------------------------------------------------------------------------------------------------
step 2 "resource integrity"
CHECKSUMS="$MAC_DIR/Docs/original-source-checksums.sha256"
check_copy() {    # <original path in the checksum file> <Mac copy relative to mac/>
    local want got
    want="$(awk -v p="$1" '$2 == p { print $1 }' "$CHECKSUMS")"
    [ -n "$want" ] || fail "no checksum line for $1"
    [ -f "$MAC_DIR/$2" ] || fail "missing Mac copy $2"
    got="$(shasum -a 256 "$MAC_DIR/$2" | awk '{ print $1 }')"
    [ "$want" = "$got" ] || fail "$2 differs from $1 ($got ≠ $want)"
    ok "$2 = $1"
}
check_copy "AA/Assets/Splash.png" "Sources/AA/Resources/Splash.png"
check_copy "AA/Sire/Data/sire2_question_bank.json" "Sources/AACore/Resources/sire2_question_bank.json"
check_copy "AA/AA.ico" "Resources/AA.ico"

# ---------------------------------------------------------------------------------------------------------------
step 3 "compile ($CONFIGURATION)"
BINARIES=()
FIRST_BIN_DIR=""
cd "$MAC_DIR"
for arch in $ARCHS; do
    triple="$arch-apple-macosx26.0"
    log="$T/build-$arch.log"
    echo "  … $triple"
    set +e
    swift build -c "$CONFIGURATION" --triple "$triple" --product AA -j "$AA_JOBS" -Xswiftc -warnings-as-errors \
        > "$log" 2>&1
    status=$?
    set -e
    if [ $status -ne 0 ]; then tail -n 40 "$log" >&2; fail "swift build failed for $arch"; fi
    if grep -q "warning:" "$log"; then grep "warning:" "$log" >&2; fail "warnings in the $arch build log"; fi
    bin_dir="$(swift build -c "$CONFIGURATION" --triple "$triple" --show-bin-path)"
    [ -x "$bin_dir/AA" ] || fail "no AA binary in $bin_dir"
    # Every triple may share one products folder: keep this slice before the next build overwrites it.
    built_archs="$(lipo -archs "$bin_dir/AA")"
    [ "$built_archs" = "$arch" ] || fail "$bin_dir/AA is '$built_archs', expected $arch"
    cp "$bin_dir/AA" "$T/AA-$arch"
    BINARIES+=("$T/AA-$arch")
    [ -n "$FIRST_BIN_DIR" ] || FIRST_BIN_DIR="$bin_dir"
    ok "$arch → $bin_dir/AA"
done

# ---------------------------------------------------------------------------------------------------------------
if [ "$SKIP_TESTS" = "1" ]; then
    step 4 "tests (skipped: SKIP_TESTS=1)"
else
    step 4 "tests"
    set +e
    swift test -j "$AA_JOBS" -Xswiftc -warnings-as-errors > "$T/test.log" 2>&1
    status=$?
    set -e
    if [ $status -ne 0 ]; then tail -n 60 "$T/test.log" >&2; fail "swift test failed"; fi
    ok "$(grep -E "Test run with" "$T/test.log" | tail -n 1 | sed 's/^[^A-Za-z]*//')"
fi

# ---------------------------------------------------------------------------------------------------------------
step 5 "assemble"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
if [ "${#BINARIES[@]}" -gt 1 ]; then
    lipo -create -output "$CONTENTS/MacOS/AA" "${BINARIES[@]}"
else
    cp "${BINARIES[0]}" "$CONTENTS/MacOS/AA"
fi
chmod 0755 "$CONTENTS/MacOS/AA"
ok "Contents/MacOS/AA ($(lipo -archs "$CONTENTS/MacOS/AA"))"

# ---------------------------------------------------------------------------------------------------------------
step 6 "symbols"
xcrun dsymutil "$CONTENTS/MacOS/AA" -o "$T/AA.app.dSYM" >/dev/null 2>&1 || fail "dsymutil"
if [ "$STRIP" = "1" ]; then
    xcrun strip -S -x "$CONTENTS/MacOS/AA"
    ok "dSYM written, binary stripped"
else
    ok "dSYM written (STRIP=0: not stripped)"
fi

# ---------------------------------------------------------------------------------------------------------------
step 7 "Info.plist"
BUILD_DATE="$(date -u +%F)"
GIT_COMMIT="$(git -C "$MAC_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$MAC_DIR" status --porcelain 2>/dev/null || true)" ]; then GIT_COMMIT="$GIT_COMMIT-dirty"; fi
sed -e "s/@VERSION@/$VERSION/g" -e "s/@BUILD@/$BUILD_NUMBER/g" -e "s/@BUILDDATE@/$BUILD_DATE/g" \
    -e "s/@GITCOMMIT@/$GIT_COMMIT/g" "$MAC_DIR/Packaging/Info.plist" > "$CONTENTS/Info.plist"
if [ -n "${AA_BAKE_DATA_DIR:-}" ]; then
    case "$AA_BAKE_DATA_DIR" in /*) ;; *) fail "AA_BAKE_DATA_DIR must be an absolute path" ;; esac
    json_path="$(printf '%s' "$AA_BAKE_DATA_DIR" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    plutil -insert LSEnvironment -json "{\"AA_DATA_DIR\":\"$json_path\"}" "$CONTENTS/Info.plist"
    echo "  ! baked LSEnvironment AA_DATA_DIR=$AA_BAKE_DATA_DIR (machine-specific; SHELL-195)"
fi
plutil -lint "$CONTENTS/Info.plist" >/dev/null || fail "Info.plist lint"
printf 'APPL????' > "$CONTENTS/PkgInfo"
ok "Info.plist ($VERSION / $BUILD_NUMBER / $BUILD_DATE / $GIT_COMMIT), PkgInfo"

# ---------------------------------------------------------------------------------------------------------------
step 8 "resources"
RES="$CONTENTS/Resources"
cp "$MAC_DIR/Sources/AA/Resources/Splash.png" "$RES/Splash.png"
cp "$MAC_DIR/Sources/AACore/Resources/sire2_question_bank.json" "$RES/sire2_question_bank.json"
cp "$MAC_DIR/Sources/AA/Resources/MenuBarIconTemplate.png" "$RES/MenuBarIconTemplate.png"
cp "$MAC_DIR/Sources/AA/Resources/MenuBarIconTemplate@2x.png" "$RES/MenuBarIconTemplate@2x.png"
bundles=0
for b in "$FIRST_BIN_DIR"/*.bundle; do
    [ -d "$b" ] || continue
    ditto "$b" "$RES/$(basename "$b")"
    bundles=$((bundles + 1))
done
ok "flat resources + $bundles SwiftPM resource bundle(s)"

# Icon (BD.3.10): the 1024-px re-draw when present, else the 256-px ICO frame upscaled.
ICON_SRC="$MAC_DIR/Resources/AppIcon-1024.png"
if [ ! -f "$ICON_SRC" ]; then
    sips -s format png "$MAC_DIR/Resources/AA.ico" --out "$T/icon256.png" >/dev/null
    ICON_SRC="$T/icon256.png"
    echo "  ! AppIcon: upscaling the 256-px ICO frame for 512/1024 slots"
fi
ICONSET="$T/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "icon_16x16:16" "icon_16x16@2x:32" "icon_32x32:32" "icon_32x32@2x:64" "icon_128x128:128" \
            "icon_128x128@2x:256" "icon_256x256:256" "icon_256x256@2x:512" "icon_512x512:512" "icon_512x512@2x:1024"; do
    sips -z "${spec##*:}" "${spec##*:}" "$ICON_SRC" --out "$ICONSET/${spec%%:*}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
if [ -d "$MAC_DIR/Resources/AppIcon.icon" ]; then
    xcrun actool "$MAC_DIR/Resources/AppIcon.icon" --compile "$RES" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$T/icon.plist" >/dev/null
    plutil -replace CFBundleIconName -string AppIcon "$CONTENTS/Info.plist"
    ok "AppIcon.icns + Assets.car"
else
    ok "AppIcon.icns ($(basename "$ICON_SRC"))"
fi

# ---------------------------------------------------------------------------------------------------------------
step 9 "clean"
xattr -cr "$APP"
find "$APP" -name .DS_Store -delete
[ -z "$(find "$APP" -type l)" ] || fail "symbolic links inside the bundle"
ok "no extended attributes, .DS_Store or symlinks"

# ---------------------------------------------------------------------------------------------------------------
step 10 "sign"
SIGN_ARGS=(--force --options runtime --entitlements "$MAC_DIR/Packaging/AA.entitlements" --sign "$SIGN_IDENTITY")
[ "$SIGN_IDENTITY" = "-" ] || SIGN_ARGS+=(--timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
ok "signed (${SIGN_IDENTITY/#-/ad-hoc}, hardened runtime)"

# ---------------------------------------------------------------------------------------------------------------
step 11 "verify (BD.7.4)"
P="$CONTENTS/Info.plist"; X="$CONTENTS/MacOS/AA"
expect_eq() {   # <label> <actual> <expected>
    [ "$2" = "$3" ] || fail "$1: '$2' ≠ '$3'"
    ok "$1"
}
plist() { plutil -extract "$1" raw "$P" 2>/dev/null || true; }
plutil -lint "$P" | grep -q ": OK$" || fail "plutil -lint"
expect_eq "CFBundleIdentifier" "$(plist CFBundleIdentifier)" "com.eriskay.aa"
expect_eq "CFBundleExecutable" "$(plist CFBundleExecutable)" "AA"
expect_eq "LSMinimumSystemVersion" "$(plist LSMinimumSystemVersion)" "26.0"
expect_eq "LSApplicationCategoryType" "$(plist LSApplicationCategoryType)" "public.app-category.productivity"
expect_eq "NSHumanReadableCopyright" "$(plist NSHumanReadableCopyright)" "Created by B.E.P. Avida - May 2026"
expect_eq "NSCameraUsageDescription" "$(plist NSCameraUsageDescription)" \
    "AA uses the camera only during Flash Sync ▸ Receive, to read the QR codes your iPhone shows on its screen. Video is never recorded, saved or sent anywhere."
expect_eq "UTExportedTypeDeclarations.0" "$(plist UTExportedTypeDeclarations.0.UTTypeIdentifier)" "com.eriskay.aa.bundle"
expect_eq "CFBundleShortVersionString" "$(plist CFBundleShortVersionString)" "$VERSION"
expect_eq "CFBundleVersion" "$(plist CFBundleVersion)" "$BUILD_NUMBER"
for absent in NSMicrophoneUsageDescription LSUIElement LSBackgroundOnly NSRequiresAquaSystemAppearance CFBundleURLTypes \
              LSMultipleInstancesProhibited NSAppTransportSecurity NSAppSleepDisabled NSLocalNetworkUsageDescription \
              ATSApplicationFontsPath; do
    if plutil -extract "$absent" raw "$P" >/dev/null 2>&1; then fail "$absent must be absent"; fi
done
if [ -z "${AA_BAKE_DATA_DIR:-}" ] && plutil -extract LSEnvironment raw "$P" >/dev/null 2>&1; then
    fail "LSEnvironment must be absent"
fi
ok "forbidden keys absent"
expect_eq "PkgInfo" "$(head -c 8 "$CONTENTS/PkgInfo")" "APPL????"
want_archs="$(echo $ARCHS | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
have_archs="$(lipo -archs "$X" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "lipo -archs" "$have_archs" "$want_archs"
for arch in $ARCHS; do
    minos="$(xcrun vtool -arch "$arch" -show-build "$X" | awk '/minos/ { print $2 }' | head -n 1)"
    expect_eq "minos ($arch)" "$minos" "26.0"
done
for arch in $ARCHS; do
    foreign="$(otool -L -arch "$arch" "$X" | tail -n +2 \
        | grep -v -E '^[[:space:]]+(/usr/lib/|/System/Library/Frameworks/)' || true)"
    [ -z "$foreign" ] || fail "non-system libraries linked ($arch): $foreign"
done
ok "links only /usr/lib and /System/Library/Frameworks"
[ ! -e "$CONTENTS/Frameworks" ] || fail "Contents/Frameworks must not exist"
[ -z "$(find "$APP" -type l)" ] || fail "symlinks in the bundle"
ok "no Frameworks/, no symlinks"
codesign --verify --strict --verbose=2 "$APP" > "$T/verify.log" 2>&1 || { cat "$T/verify.log" >&2; fail "codesign --verify"; }
grep -q "valid on disk" "$T/verify.log" || fail "signature not valid on disk"
grep -q "satisfies its Designated Requirement" "$T/verify.log" || fail "designated requirement"
ok "codesign --verify --strict"
codesign -d --verbose=2 "$APP" > "$T/sig.log" 2>&1
grep -q "^Identifier=com.eriskay.aa$" "$T/sig.log" || fail "signature identifier"
if [ "$SIGN_IDENTITY" = "-" ]; then
    grep -q "flags=0x10002(adhoc,runtime)" "$T/sig.log" || { cat "$T/sig.log" >&2; fail "expected flags=0x10002(adhoc,runtime)"; }
    grep -q "^Signature=adhoc$" "$T/sig.log" || fail "expected Signature=adhoc"
else
    grep -q "runtime" "$T/sig.log" || fail "hardened runtime flag missing"
fi
ok "signature identifier and flags"
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$T/ent.plist"
ent_keys="$(plutil -convert json -o - "$T/ent.plist" 2>/dev/null || echo '{}')"
expect_eq "entitlements" "$ent_keys" '{"com.apple.security.device.camera":true}'
expect_eq "sire2_question_bank.json sha256" "$(shasum -a 256 "$CONTENTS/Resources/sire2_question_bank.json" | awk '{print $1}')" \
    "e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf"
expect_eq "Splash.png sha256" "$(shasum -a 256 "$CONTENTS/Resources/Splash.png" | awk '{print $1}')" \
    "1489fd928894042eda13a510b6916eb18ccb0310fa54b035d2e82682a84539a6"
HOST_ARCH="$(uname -m)"
version_out="$("$X" --version)"
expect_eq "--version ($HOST_ARCH)" "$version_out" "AA $VERSION ($BUILD_NUMBER) $HOST_ARCH"
if [[ " $ARCHS " == *" x86_64 "* ]] && [ "$HOST_ARCH" != "x86_64" ]; then
    if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
        expect_eq "--version (x86_64 via Rosetta)" "$(arch -x86_64 "$X" --version)" "AA $VERSION ($BUILD_NUMBER) x86_64"
    else
        echo "  · x86_64 slice not executed (Rosetta not installed)"
    fi
fi
APP_MB="$(du -sm "$APP" | cut -f1)"
[ "$APP_MB" -le "$AA_MAX_APP_MB" ] || fail "AA.app is $APP_MB MB (tripwire $AA_MAX_APP_MB MB)"
ok "size $APP_MB MB ≤ $AA_MAX_APP_MB MB"

# ---------------------------------------------------------------------------------------------------------------
step 12 "publish"
mkdir -p "$DIST"
rm -rf "$DIST/AA.app" "$DIST/AA.app.dSYM"
mv "$APP" "$DIST/AA.app"
mv "$T/AA.app.dSYM" "$DIST/AA.app.dSYM"
APP="$DIST/AA.app"
ok "$DIST/AA.app"

# ---------------------------------------------------------------------------------------------------------------
ZIP=""
DMG=""
package() {
    rm -rf "$T/pkg"
    mkdir -p "$T/pkg/AA"
    ditto "$APP" "$T/pkg/AA/AA.app"
    cp "$MAC_DIR/Packaging/Install.txt" "$T/pkg/AA/Install.txt"
    if [ "$PORTABLE_LAUNCHER" = "1" ]; then
        cp "$MAC_DIR/Packaging/AA (portable).command" "$T/pkg/AA/AA (portable).command"
        chmod 0755 "$T/pkg/AA/AA (portable).command"
    fi
    ZIP="$DIST/AA-$VERSION-$BUILD_NUMBER-macOS.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$T/pkg/AA" "$ZIP"
    if [ "$PACKAGE" = "dmg" ]; then
        DMG="$DIST/AA-$VERSION-$BUILD_NUMBER-macOS.dmg"
        hdiutil create -volname AA -srcfolder "$T/pkg/AA" -ov -format UDZO "$DMG" >/dev/null
    fi
    ( cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" ${DMG:+"$(basename "$DMG")"} > SHA256SUMS )
}
if [ "$PACKAGE" = "none" ]; then
    step 13 "package (skipped: PACKAGE=none)"
else
    step 13 "package"
    package
    ok "$ZIP${DMG:+ and $DMG}; SHA256SUMS"
fi

# ---------------------------------------------------------------------------------------------------------------
if [ -n "${NOTARY_PROFILE:-}" ] && [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]] && [ -n "$ZIP" ]; then
    step 14 "notarise"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    package
    ok "notarised and stapled; package rebuilt"
else
    step 14 "notarise (skipped: needs a Developer ID identity and NOTARY_PROFILE)"
fi

# ---------------------------------------------------------------------------------------------------------------
step 15 "summary"
SIGNATURE="adhoc"
[ "$SIGN_IDENTITY" = "-" ] || SIGNATURE="$SIGN_IDENTITY"
ARCH_LIST="$(lipo -archs "$APP/Contents/MacOS/AA")"
APP_SIZE="$(du -sk "$APP" | awk '{ printf "%.1f", $1 / 1024 }')"
echo
printf 'AA.app      mac/%s  (%s MB, %s, minos 26.0)\n' "${APP#"$MAC_DIR/"}" "$APP_SIZE" "$ARCH_LIST"
printf 'Version     %s (%s)  %s  %s\n' "$VERSION" "$BUILD_NUMBER" "$BUILD_DATE" "$GIT_COMMIT"
printf 'Signature   %s, hardened runtime, entitlements: com.apple.security.device.camera\n' "$SIGNATURE"
if [ -n "$ZIP" ]; then
    printf 'Package     mac/%s  sha256 %s\n' "${ZIP#"$MAC_DIR/"}" "$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
fi
exit 0
