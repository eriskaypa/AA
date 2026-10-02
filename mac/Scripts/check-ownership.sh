#!/bin/bash
# check-ownership.sh — ownership and merge-safety gate for the Swift port (owner: F1).
# Spec: ARCHITECTURE.md §1.1 (only .swift files in target folders, unique basenames), §10.6 (gate), §11
# (placeholders other stages create in an owner's folder), §12.1–§12.2 (path ownership, namespacing);
# OWNERSHIP.md §2 (the authoritative path table, encoded in owner_of below).
#
# Usage (run from anywhere; paths are relative to mac/):
#   Scripts/check-ownership.sh [--owner <id>] [--base <ref>] [--no-paths]
#   Scripts/check-ownership.sh --owner-of <path>...    print "<owner><TAB><path>" for each path
#                                                       (owner "-" = unowned, "*" = shared running record)
#
# Checks (every failure is listed; exit 1 if any check fails, 2 on a usage error):
#   1. paths    — every path changed on this branch (committed since <base>, plus staged, unstaged and untracked
#                 changes) belongs to the branch owner. Owner: --owner, else $AA_OWNER, else the branch name
#                 (wave/<id>, stage/<id>; mac-port = F1). Base: --base, else `git merge-base HEAD mac-port` on
#                 wave/stage branches; on mac-port only uncommitted changes are checked (the integration branch
#                 holds everyone's merged work). Skipped with a note during a merge, on other branches, with
#                 --no-paths or AA_OWNER=none. Exceptions (ARCH §11, OWNERSHIP §2 notes): F1 may add placeholder
#                 files in other owners' AACore folders, the AA bootstrap (Sources/AA/App/AAMain.swift) and
#                 Tools/FlashSyncInterop/main.swift, plus the manifest resources under Sources/AA/Resources/; F3 may
#                 add placeholder files anywhere under Sources/AA/. A placeholder file's FIRST line must be
#                 "// PLACEHOLDER(<owner of that path>)". Nothing outside mac/ may change (rule zero).
#   2. files    — only .swift files under Sources/** (except the manifest's resources), Tests/AACoreTests/**
#                 outside Fixtures/, and Tools/FlashSyncInterop/**.
#   3. names    — .swift basenames are unique within each target (AACore, AA, AACoreTests, AAFlashSyncInterop).
#   4. symbols  — no non-private top-level class/struct/enum/protocol/actor/func/typealias name is declared in
#                 files of two different owners anywhere in Sources/**, Tests/** and Tools/FlashSyncInterop/**
#                 (line scan of column-0 declarations; private/fileprivate declarations are ignored).
#
# Requires only /bin/bash 3.2, git, awk, sort, find (stock macOS).

set -u
export LC_ALL=C

MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(git -C "$MAC_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
cd "$MAC_DIR" || exit 2

# The manifest's resources (ARCHITECTURE.md §1.1) — the only non-Swift files allowed under Sources/**.
MANIFEST_RESOURCES="Sources/AACore/Resources/sire2_question_bank.json
Sources/AA/Resources/Splash.png
Sources/AA/Resources/MenuBarIconTemplate.png
Sources/AA/Resources/MenuBarIconTemplate@2x.png"

KNOWN_OWNERS="lead F1 F2 F3 W-SHELL W-PERSIST W-GOLD W-RICH W-CONT W-FILES W-HIER W-BUILD W-PLAN W-QUICK W-CREW
W-VESSEL W-PDF W-SIRE W-FLASH W-DRIVE"

# ---------------------------------------------------------------------------------------------------------------
# OWNERSHIP.md §2, encoded. Sets REPLY to the owner of a mac/-relative path ("" = unowned, "*" = shared).
# The first matching pattern wins, so the specific rows come before the general ones.
owner_of() {
    REPLY=""
    case "$1" in
        Docs/Requests/*.md|Docs/Deviations/*.md)
            REPLY="${1##*/}"; REPLY="${REPLY%.md}"
            case " $(echo $KNOWN_OWNERS) " in *" $REPLY "*) ;; *) REPLY="" ;; esac ;;
        # Running record of the port; every stage appends its own row (not in the §2 table).
        Docs/PROGRESS.md) REPLY="*" ;;
        Docs/ARCHITECTURE-BRIEF.md|Docs/DECISIONS.md|Docs/Spec/*|Docs/original-source-checksums.sha256|\
        Docs/ARCHITECTURE.md|Docs/OWNERSHIP.md|Docs/DEVIATIONS.md) REPLY=lead ;;

        # F1
        Package.swift|.gitignore|Scripts/check-placeholders.sh|Scripts/check-ownership.sh) REPLY=F1 ;;
        Sources/AACore/Foundation/*|Sources/AACore/JSON/*|Sources/AACore/Model/*|Sources/AACore/Persistence/*|\
        Sources/AACore/Crypto/*|Sources/AACore/Zip/*|Sources/AACore/Xlsx/*|Sources/AACore/Resources/*) REPLY=F1 ;;
        Sources/AACore/Store/AppStore.swift|Sources/AACore/Store/PersistenceWriter.swift) REPLY=F1 ;;
        Tests/AACoreTests/Support/*|Tests/AACoreTests/Foundation/*|Tests/AACoreTests/JSON/*|\
        Tests/AACoreTests/Model/*|Tests/AACoreTests/Persistence/*|Tests/AACoreTests/Crypto/*|\
        Tests/AACoreTests/Zip/*|Tests/AACoreTests/Xlsx/*|Tests/AACoreTests/Store/*) REPLY=F1 ;;
        Tests/AACoreTests/Fixtures/foundation/*|Tests/AACoreTests/Fixtures/json/*|\
        Tests/AACoreTests/Fixtures/model/*|Tests/AACoreTests/Fixtures/persistence/*|\
        Tests/AACoreTests/Fixtures/zip/*|Tests/AACoreTests/Fixtures/xlsxwriter/*) REPLY=F1 ;;

        # F2
        Sources/AACore/Store/AppStore+Lookups.swift|Sources/AACore/Store/AppStore+Relations.swift|\
        Sources/AACore/Store/AppStore+Log.swift|Sources/AACore/Store/AppStore+Trash.swift|\
        Sources/AACore/Store/AppStore+Recurrence.swift|Sources/AACore/Store/AppStore+Groups.swift|\
        Sources/AACore/Store/AppStore+Creation.swift) REPLY=F2 ;;
        Sources/AACore/Services/*|Sources/AACore/XlsxRead/*) REPLY=F2 ;;
        Tests/AACoreTests/Services/*|Tests/AACoreTests/StoreDomain/*|Tests/AACoreTests/XlsxRead/*) REPLY=F2 ;;
        Tests/AACoreTests/Fixtures/services/*|Tests/AACoreTests/Fixtures/xlsx/*) REPLY=F2 ;;

        # F3
        Sources/AACore/Launch/*|Sources/AACore/Commands/*) REPLY=F3 ;;
        Sources/AA/App/*|Sources/AA/Shell/*|Sources/AA/Commands/*|Sources/AA/Design/*|Sources/AA/Shared/*|\
        Sources/AA/Debug/*|Sources/AA/Resources/*) REPLY=F3 ;;
        Tests/AACoreTests/Launch/*|Tests/AACoreTests/Commands/*) REPLY=F3 ;;
        Tests/AACoreTests/Fixtures/launch/*|Tests/AACoreTests/Fixtures/ui/f3/*) REPLY=F3 ;;

        # W-SHELL
        README.md|VERSION|Packaging/*|Resources/*|Scripts/build-app.sh) REPLY=W-SHELL ;;
        Sources/AACore/ShellSupport/*|Sources/AA/ShellFeatures/*|Tests/AACoreTests/ShellSupport/*) REPLY=W-SHELL ;;
        Tests/AACoreTests/Fixtures/shell/*|Tests/AACoreTests/Fixtures/ui/w-shell/*) REPLY=W-SHELL ;;

        # W-PERSIST
        Sources/AACore/Bundles/*|Sources/AACore/Attachments/*|Sources/AACore/SharedSave/*|\
        Sources/AACore/Instance/*|Sources/AA/PersistenceUI/*) REPLY=W-PERSIST ;;
        Tests/AACoreTests/Bundles/*|Tests/AACoreTests/Attachments/*|Tests/AACoreTests/SharedSave/*|\
        Tests/AACoreTests/Instance/*) REPLY=W-PERSIST ;;
        Tests/AACoreTests/Fixtures/bundles/*|Tests/AACoreTests/Fixtures/settings/*|\
        Tests/AACoreTests/Fixtures/attachments/*|Tests/AACoreTests/Fixtures/ui/w-persist/*) REPLY=W-PERSIST ;;

        # W-GOLD (before W-RICH: the two xaml capture folders are W-GOLD's)
        Tools/global.json|Tools/WinFixtures/*|Tools/WinCapture/*|Tools/XlsxGolden/*|Scripts/fixtures.sh) REPLY=W-GOLD ;;
        Tests/AACoreTests/WinFixtures/*) REPLY=W-GOLD ;;
        Tests/AACoreTests/Fixtures/winfixtures/*|Tests/AACoreTests/Fixtures/mac-out/*|\
        Tests/AACoreTests/Fixtures/xaml/wpf-capture/*|Tests/AACoreTests/Fixtures/xaml/mac-roundtrip/*) REPLY=W-GOLD ;;

        # W-RICH
        Sources/AACore/RichText/*|Tests/AACoreTests/RichText/*) REPLY=W-RICH ;;
        Tests/AACoreTests/Fixtures/xaml/*|Tests/AACoreTests/Fixtures/html/*) REPLY=W-RICH ;;

        # W-CONT
        Sources/AACore/Editor/*|Sources/AA/Editor/*|Tests/AACoreTests/Editor/*) REPLY=W-CONT ;;
        Tests/AACoreTests/Fixtures/editor/*|Tests/AACoreTests/Fixtures/ui/w-cont/*) REPLY=W-CONT ;;

        # W-FILES
        Sources/AACore/FileBank/*|Sources/AA/FileBank/*|Tests/AACoreTests/FileBank/*) REPLY=W-FILES ;;
        Tests/AACoreTests/Fixtures/filebank/*|Tests/AACoreTests/Fixtures/ui/w-files/*) REPLY=W-FILES ;;

        # W-HIER
        Sources/AACore/Hierarchy/*|Sources/AA/Hierarchy/*|Tests/AACoreTests/Hierarchy/*) REPLY=W-HIER ;;
        Tests/AACoreTests/Fixtures/hierarchy/*|Tests/AACoreTests/Fixtures/ui/w-hier/*) REPLY=W-HIER ;;

        # W-BUILD
        Sources/AACore/Builders/*|Sources/AA/Builders/*|Tests/AACoreTests/Builders/*) REPLY=W-BUILD ;;
        Tests/AACoreTests/Fixtures/builders/*|Tests/AACoreTests/Fixtures/ui/w-build/*) REPLY=W-BUILD ;;

        # W-PLAN
        Sources/AACore/Calendar/*|Sources/AACore/Board/*|Sources/AA/Calendar/*|Sources/AA/Board/*|\
        Tests/AACoreTests/Calendar/*|Tests/AACoreTests/Board/*) REPLY=W-PLAN ;;
        Tests/AACoreTests/Fixtures/calendar/*|Tests/AACoreTests/Fixtures/board/*|\
        Tests/AACoreTests/Fixtures/ui/w-plan/*) REPLY=W-PLAN ;;

        # W-QUICK
        Sources/AACore/QuickWork/*|Sources/AACore/Windows/*|Sources/AA/QuickWork/*|Sources/AA/Windows/*|\
        Tests/AACoreTests/QuickWork/*|Tests/AACoreTests/Windows/*) REPLY=W-QUICK ;;
        Tests/AACoreTests/Fixtures/quickwork/*|Tests/AACoreTests/Fixtures/windows/*|\
        Tests/AACoreTests/Fixtures/ui/w-quick/*) REPLY=W-QUICK ;;

        # W-CREW
        Sources/AACore/Crew/*|Sources/AA/Crew/*|Tests/AACoreTests/Crew/*) REPLY=W-CREW ;;
        Tests/AACoreTests/Fixtures/crew/*|Tests/AACoreTests/Fixtures/ui/w-crew/*) REPLY=W-CREW ;;

        # W-VESSEL
        Sources/AACore/Vessel/*|Sources/AA/Vessel/*|Tests/AACoreTests/Vessel/*) REPLY=W-VESSEL ;;
        Tests/AACoreTests/Fixtures/vessel/*|Tests/AACoreTests/Fixtures/ui/w-vessel/*) REPLY=W-VESSEL ;;

        # W-PDF
        Sources/AACore/Export/*|Sources/AA/Export/*|Tests/AACoreTests/Export/*) REPLY=W-PDF ;;
        Tests/AACoreTests/Fixtures/pdf/*|Tests/AACoreTests/Fixtures/ui/w-pdf/*) REPLY=W-PDF ;;

        # W-SIRE
        Sources/AACore/Sire/*|Sources/AA/Sire/*|Tests/AACoreTests/Sire/*) REPLY=W-SIRE ;;
        Tests/AACoreTests/Fixtures/sire/*|Tests/AACoreTests/Fixtures/ui/w-sire/*) REPLY=W-SIRE ;;

        # W-FLASH
        Sources/AACore/FlashSync/*|Sources/AA/FlashSync/*|Tools/FlashSyncInterop/*|Tests/AACoreTests/FlashSync/*) REPLY=W-FLASH ;;
        Tests/AACoreTests/Fixtures/flashsync/*|Tests/AACoreTests/Fixtures/ui/w-flash/*) REPLY=W-FLASH ;;

        # W-DRIVE
        Sources/AACore/GoogleDrive/*|Sources/AACore/Tools/*|Sources/AA/Drive/*|Sources/AA/Tools/*|\
        Tests/AACoreTests/GoogleDrive/*|Tests/AACoreTests/Tools/*) REPLY=W-DRIVE ;;
        Tests/AACoreTests/Fixtures/drive/*|Tests/AACoreTests/Fixtures/tools/*|\
        Tests/AACoreTests/Fixtures/ui/w-drive/*) REPLY=W-DRIVE ;;
    esac
}

# ---------------------------------------------------------------------------------------------------------------
# Argument parsing.
OWNER="${AA_OWNER:-}"
BASE=""
DO_PATHS=1
if [ "${1:-}" = "--owner-of" ]; then
    shift
    for p in "$@"; do
        p="${p#./}"; p="${p#mac/}"
        owner_of "$p"
        printf '%s\t%s\n' "${REPLY:--}" "$p"
    done
    exit 0
fi
while [ $# -gt 0 ]; do
    case "$1" in
        --owner) OWNER="${2:-}"; shift 2 || { echo "usage: --owner <id>" >&2; exit 2; } ;;
        --base) BASE="${2:-}"; shift 2 || { echo "usage: --base <ref>" >&2; exit 2; } ;;
        --no-paths) DO_PATHS=0; shift ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "check-ownership: unknown argument '$1' (see --help)" >&2; exit 2 ;;
    esac
done

FAILED=0
fail() { FAILED=1; echo "  ✗ $*"; }
note() { echo "  · $*"; }

# ---------------------------------------------------------------------------------------------------------------
# 1. Path ownership.
echo "check-ownership: 1/4 paths"
BRANCH="$(git -C "$MAC_DIR" symbolic-ref --short -q HEAD 2>/dev/null || true)"
if [ -z "$OWNER" ]; then
    case "$BRANCH" in
        wave/*|stage/*) OWNER="${BRANCH#*/}" ;;
        mac-port) OWNER=F1 ;;
    esac
fi
if [ $DO_PATHS -eq 0 ]; then note "--no-paths — path check skipped"; fi
if [ $DO_PATHS -eq 1 ] && [ "$OWNER" = "none" ]; then note "AA_OWNER=none — path check skipped"; DO_PATHS=0; fi
if [ $DO_PATHS -eq 1 ] && [ -z "$REPO_DIR" ]; then note "not a git checkout — path check skipped"; DO_PATHS=0; fi
if [ $DO_PATHS -eq 1 ] && git -C "$MAC_DIR" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    note "merge in progress — merged-tree mode, path check skipped"; DO_PATHS=0
fi
if [ $DO_PATHS -eq 1 ] && [ -z "$OWNER" ]; then
    note "branch '${BRANCH:-detached}' has no owner (use --owner <id> or AA_OWNER) — path check skipped"; DO_PATHS=0
fi
if [ $DO_PATHS -eq 1 ]; then
    case " $(echo $KNOWN_OWNERS) " in
        *" $OWNER "*) ;;
        *) echo "check-ownership: unknown owner id '$OWNER'" >&2; exit 2 ;;
    esac
    if [ -z "$BASE" ]; then
        case "$BRANCH" in
            wave/*|stage/*)
                BASE="$(git -C "$MAC_DIR" merge-base HEAD mac-port 2>/dev/null \
                        || git -C "$MAC_DIR" merge-base HEAD origin/mac-port 2>/dev/null || true)"
                [ -n "$BASE" ] || note "no merge-base with mac-port — only uncommitted changes are checked" ;;
        esac
    fi
    CHANGES="$(mktemp -t aa-ownership)"
    trap 'rm -f "$CHANGES" "${SYMS:-}" "${SYMS_OWNED:-}"' EXIT
    # Committed changes since BASE: "<status><TAB><repo-relative path>" (renames split into D + A).
    if [ -n "$BASE" ]; then
        if ! git -C "$REPO_DIR" rev-parse -q --verify "$BASE^{commit}" >/dev/null; then
            echo "check-ownership: --base '$BASE' is not a commit" >&2; exit 2
        fi
        git -C "$REPO_DIR" diff --name-status -M --no-color "$BASE" HEAD | awk -F'\t' '
            $1 ~ /^R/ { print "D\t" $2; print "A\t" $3; next }
            $1 ~ /^C/ { print "A\t" $3; next }
            { print substr($1, 1, 1) "\t" $2 }' >> "$CHANGES"
    fi
    # Uncommitted changes (staged, unstaged, untracked; ignored files excluded).
    git -C "$REPO_DIR" status --porcelain=v1 --untracked-files=all --no-renames | awk '
        { xy = substr($0, 1, 2); p = substr($0, 4)
          if (p ~ /^".*"$/) { p = substr(p, 2, length(p) - 2) }
          if (xy == "??") s = "U"; else if (xy ~ /D/) s = "D"; else if (xy ~ /A/) s = "A"; else s = "M"
          print s "\t" p }' >> "$CHANGES"
    checked=0
    while IFS="$(printf '\t')" read -r st rp; do
        [ -n "$rp" ] || continue
        case "$rp" in */.DS_Store|.DS_Store) continue ;; esac
        case "$rp" in
            mac/*) p="${rp#mac/}" ;;
            *)
                if [ "$st" = "U" ]; then note "untracked file outside mac/ (not committable): $rp"
                else fail "rule zero — change outside mac/: $rp"; fi
                continue ;;
        esac
        checked=$((checked + 1))
        owner_of "$p"; powner="$REPLY"
        [ "$powner" = "*" ] && continue
        [ "$powner" = "$OWNER" ] && continue
        if [ -z "$powner" ]; then fail "unowned path (not in OWNERSHIP.md §2): $p"; continue; fi
        # Placeholder exceptions (ARCH §11).
        if [ "$st" != "D" ] && [ -f "$p" ]; then
            allowed=0
            if [ "$OWNER" = "F1" ]; then
                case "$p" in
                    Sources/AACore/Launch/*|Sources/AACore/Commands/*) ;;
                    Sources/AACore/*|Sources/AA/App/AAMain.swift|Tools/FlashSyncInterop/main.swift) allowed=1 ;;
                esac
                case "$p" in
                    Sources/AA/Resources/*)
                        if printf '%s\n' "$MANIFEST_RESOURCES" | grep -qxF "$p"; then continue; fi ;;
                esac
            elif [ "$OWNER" = "F3" ]; then
                case "$p" in Sources/AA/*) allowed=1 ;; esac
            fi
            if [ $allowed -eq 1 ] && head -n 1 "$p" | grep -q "^// PLACEHOLDER($powner)"; then continue; fi
        fi
        fail "$OWNER may not change $p (owner $powner)"
    done < "$CHANGES"
    if [ -n "$BASE" ]; then note "owner $OWNER, base $(git -C "$MAC_DIR" rev-parse --short "$BASE"): $checked path(s) checked"
    else note "owner $OWNER, uncommitted changes only: $checked path(s) checked"; fi
fi

# ---------------------------------------------------------------------------------------------------------------
# 2. Only .swift files in target folders.
echo "check-ownership: 2/4 non-Swift files in targets"
nonswift=0
while IFS= read -r f; do
    f="${f#./}"
    [ -n "$f" ] || continue
    case "$f" in *.swift) continue ;; esac
    case "$f" in Tests/AACoreTests/Fixtures/*) continue ;; esac
    if printf '%s\n' "$MANIFEST_RESOURCES" | grep -qxF "$f"; then continue; fi
    fail "non-Swift file in a target folder (declare it in Package.swift via F1, or move it): $f"
    nonswift=$((nonswift + 1))
done <<EOF
$(find Sources Tests/AACoreTests Tools/FlashSyncInterop -name '.*' -prune -o -type f -print 2>/dev/null)
EOF
[ $nonswift -eq 0 ] && note "ok"

# ---------------------------------------------------------------------------------------------------------------
# 3. Unique .swift basenames per target.
echo "check-ownership: 3/4 duplicate basenames per target"
dups=0
for target in Sources/AACore Sources/AA Tests/AACoreTests Tools/FlashSyncInterop; do
    [ -d "$target" ] || continue
    out="$(find "$target" -name '.*' -prune -o -type f -name '*.swift' -print \
           | grep -v '^Tests/AACoreTests/Fixtures/' \
           | awk -F/ '{ n = $NF; c[n]++; p[n] = p[n] "\n      " $0 }
                      END { for (n in c) if (c[n] > 1) print n " (" c[n] " files):" p[n] }')"
    if [ -n "$out" ]; then
        dups=1; FAILED=1
        echo "  ✗ $target — duplicate file names:"
        echo "$out" | sed 's/^/    /'
    fi
done
[ $dups -eq 0 ] && note "ok"

# ---------------------------------------------------------------------------------------------------------------
# 4. Cross-owner top-level symbol collisions (column-0 declarations, private/fileprivate excluded).
echo "check-ownership: 4/4 cross-owner top-level symbols"
SYMS="$(mktemp -t aa-symbols)"
SYMS_OWNED="$(mktemp -t aa-symbols-owned)"
trap 'rm -f "${CHANGES:-}" "$SYMS" "$SYMS_OWNED"' EXIT
find Sources Tests Tools/FlashSyncInterop -name '.*' -prune -o -type f -name '*.swift' -print 2>/dev/null \
    | grep -v '^Tests/AACoreTests/Fixtures/' | tr '\n' '\0' | xargs -0 awk '
    FNR == 1 { inblock = 0 }
    {
        line = $0
        # Skip the bodies of multi-line string literals ("""), which may hold column-0 text.
        n = gsub(/"""/, "\"\"\"", line)
        if (inblock) { if (n % 2 == 1) inblock = 0; next }
        if (n % 2 == 1) { inblock = 1 }
        if (line !~ /^[@A-Za-z]/) next
        rest = line; priv = 0
        while (1) {
            if (substr(rest, 1, 1) == "@") {
                if (!match(rest, /^@[A-Za-z_][A-Za-z0-9_.]*/)) break
                rest = substr(rest, RLENGTH + 1)
                if (substr(rest, 1, 1) == "(") {
                    depth = 0; len = length(rest)
                    for (i = 1; i <= len; i++) {
                        c = substr(rest, i, 1)
                        if (c == "(") depth++
                        else if (c == ")") { depth--; if (depth == 0) break }
                    }
                    rest = substr(rest, i + 1)
                }
                sub(/^[ \t]+/, "", rest); continue
            }
            if (match(rest, /^(private|fileprivate)([ \t]|\()/)) {
                if (substr(rest, RLENGTH, 1) == "(") {
                    rest = substr(rest, RLENGTH)
                    if (rest !~ /^\(set\)/) priv = 1      # private(set) only restricts a setter
                    sub(/^\([^)]*\)/, "", rest)
                } else { priv = 1; rest = substr(rest, RLENGTH + 1) }
                sub(/^[ \t]+/, "", rest); continue
            }
            if (match(rest, /^(public|internal|package|open|final|nonisolated|indirect|distributed|static|override|required|convenience|dynamic|mutating|nonmutating|isolated|consuming|borrowing|lazy|weak|unowned)([ \t]|\()/)) {
                if (substr(rest, RLENGTH, 1) == "(") { rest = substr(rest, RLENGTH); sub(/^\([^)]*\)/, "", rest) }
                else rest = substr(rest, RLENGTH + 1)
                sub(/^[ \t]+/, "", rest); continue
            }
            break
        }
        if (priv) next
        if (match(rest, /^(class|struct|enum|protocol|actor|func|typealias)[ \t]+/)) {
            kw = substr(rest, 1, RLENGTH); sub(/[ \t]+$/, "", kw)
            rest = substr(rest, RLENGTH + 1)
            if (substr(rest, 1, 1) == "`") rest = substr(rest, 2)
            if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) {
                name = substr(rest, 1, RLENGTH)
                if (kw == "class" && (name == "func" || name == "var" || name == "let")) next
                print name "\t" kw "\t" FILENAME ":" FNR
            }
        }
    }' > "$SYMS"
while IFS="$(printf '\t')" read -r name kw loc; do
    owner_of "${loc%:*}"
    printf '%s\t%s\t%s\t%s\n' "$name" "${REPLY:--}" "$kw" "$loc"
done < "$SYMS" | sort > "$SYMS_OWNED"
collisions="$(awk -F'\t' '
    { if (!(($1, $2) in seen)) { seen[$1, $2] = 1; owners[$1] = owners[$1] " " $2; count[$1]++ }
      where[$1] = where[$1] "\n      " $2 "  " $3 " " $1 "  (" $4 ")" }
    END { for (n in count) if (count[n] > 1) print n " — declared by" owners[n] ":" where[n] }' "$SYMS_OWNED")"
total="$(wc -l < "$SYMS" | tr -d ' ')"
if [ -n "$collisions" ]; then
    FAILED=1
    echo "  ✗ the same top-level name is declared by different owners (prefix or namespace it, ARCH §12.2):"
    echo "$collisions" | sed 's/^/    /'
else
    note "ok ($total top-level declarations scanned)"
fi

if [ $FAILED -ne 0 ]; then echo "check-ownership: FAILED"; exit 1; fi
echo "check-ownership: OK"
exit 0
