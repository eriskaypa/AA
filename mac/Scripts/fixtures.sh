#!/bin/bash
# fixtures.sh — thin wrapper over the golden-fixture plan (spec 01 GF.4.1, GF.8.6, DATA-313; owner W-GOLD).
#
# Usage (run from anywhere; paths are relative to mac/):
#   Scripts/fixtures.sh verify-sources            the linked Windows sources match Docs/original-source-checksums.sha256
#   Scripts/fixtures.sh generate [args…]          regenerate Tests/AACoreTests/Fixtures/winfixtures (C# oracle; .NET 10)
#                                                 args go to WinFixtures, e.g. --families a,d  or  --platform windows
#   Scripts/fixtures.sh verify-generated          CI: regenerate into a temp tree and diff (generate --verify-only)
#   Scripts/fixtures.sh selfcheck                 recompute MANIFEST.json specConflicts[] from the committed goldens
#   Scripts/fixtures.sh xlsx-golden               XlsxGolden: Fixtures/xlsx + winfixtures/xlsx-inputs → winfixtures/xlsx
#   Scripts/fixtures.sh check-mac                 reverse check of Fixtures/mac-out (writes mac-out/check-report.<p>.json)
#   Scripts/fixtures.sh verify                    swift test of the golden suites (skip cleanly when goldens are absent)
#   Scripts/fixtures.sh require                   the same with AA_REQUIRE_FIXTURES=1 (absence = failure; release gate)
#   Scripts/fixtures.sh emit-mac-out              AA_EMIT_MAC_OUT=1: the Swift emitter rewrites Fixtures/mac-out
#   Scripts/fixtures.sh emit-xlsx-inputs          AA_EMIT_XLSX_INPUTS=1: rewrites Fixtures/winfixtures/xlsx-inputs
#   Scripts/fixtures.sh ci                        verify-sources + verify-generated + require (GF.8.6 macOS job)
#   Scripts/fixtures.sh status                    what is present: manifests, case counts, mac-out, captures
#
# The C# tools are dev-only oracles (01 GF.0) and need the .NET 10 SDK: `brew install --cask dotnet-sdk`, or the
# official installer script into mac/Tools/.dotnet (gitignored) — this script uses mac/Tools/.dotnet/dotnet first.
# Every dotnet command runs from mac/Tools so mac/Tools/global.json pins the SDK band. Nothing here writes outside
# mac/ (rule zero): build output stays in mac/Tools/*/bin|obj (gitignored).

set -euo pipefail

MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$MAC_DIR/Tools"
FIX="$MAC_DIR/Tests/AACoreTests/Fixtures"
WINFIX="$FIX/winfixtures"
MACOUT="$FIX/mac-out"

dotnet_bin() {
    if [ -x "$TOOLS/.dotnet/dotnet" ]; then echo "$TOOLS/.dotnet/dotnet"; return; fi
    if command -v dotnet >/dev/null 2>&1; then command -v dotnet; return; fi
    echo "fixtures.sh: the .NET 10 SDK is not installed." >&2
    echo "  Install it (brew install --cask dotnet-sdk), or the official dotnet-install.sh with" >&2
    echo "  --channel 10.0 --install-dir mac/Tools/.dotnet  (gitignored). See mac/Tools/WinFixtures/README.md." >&2
    exit 3
}

winfixtures() {
    local dn; dn="$(dotnet_bin)"
    (cd "$TOOLS" && DOTNET_CLI_TELEMETRY_OPTOUT=1 "$dn" run --project WinFixtures -c Release -- "$@")
}

platform() {
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo windows ;; *) echo unix ;; esac
}

swift_test() {
    (cd "$MAC_DIR" && swift test -j 3 "$@")
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
    verify-sources)
        winfixtures verify-sources ;;
    generate)
        winfixtures generate --out "$WINFIX" "$@" ;;
    verify-generated)
        winfixtures generate --out "$WINFIX" --verify-only "$@" ;;
    selfcheck)
        winfixtures selfcheck --out "$WINFIX" ;;
    xlsx-golden)
        dn="$(dotnet_bin)"
        (cd "$TOOLS" && DOTNET_CLI_TELEMETRY_OPTOUT=1 "$dn" run --project XlsxGolden -c Release -- \
            --fixtures "$FIX/xlsx" --fixtures "$WINFIX/xlsx-inputs" --out "$WINFIX/xlsx" "$@") ;;
    check-mac)
        p="$(platform)"
        winfixtures check-mac "$MACOUT" --report "$MACOUT/check-report.$p.json" --platform "$p" ;;
    verify)
        swift_test --filter Gold "$@" ;;
    require)
        AA_REQUIRE_FIXTURES=1 swift_test --filter Gold "$@" ;;
    emit-mac-out)
        AA_EMIT_MAC_OUT=1 swift_test --filter GoldMacOutEmitter "$@" ;;
    emit-xlsx-inputs)
        AA_EMIT_XLSX_INPUTS=1 swift_test --filter GoldXlsxInputEmitter "$@" ;;
    ci)
        winfixtures verify-sources
        winfixtures generate --out "$WINFIX" --verify-only
        AA_REQUIRE_FIXTURES=1 swift_test --filter Gold ;;
    status)
        for m in "$WINFIX/MANIFEST.json" "$FIX/xaml/wpf-capture/MANIFEST.json"; do
            if [ -f "$m" ]; then
                n="$(grep -c '"id":' "$m" || true)"
                echo "present  ${m#$MAC_DIR/}  ($n case records)"
            else
                echo "absent   ${m#$MAC_DIR/}"
            fi
        done
        for d in "$WINFIX/xlsx" "$WINFIX/xlsx-inputs" "$MACOUT" "$FIX/xaml/mac-roundtrip"; do
            if [ -d "$d" ]; then
                echo "present  ${d#$MAC_DIR/}  ($(find "$d" -type f ! -name '.DS_Store' | wc -l | tr -d ' ') files)"
            else
                echo "absent   ${d#$MAC_DIR/}"
            fi
        done ;;
    ""|-h|--help|help)
        sed -n '2,25p' "$0" ;;
    *)
        echo "fixtures.sh: unknown command '$cmd' (see --help)" >&2
        exit 2 ;;
esac
