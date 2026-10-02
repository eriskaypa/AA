#!/bin/bash
# check-placeholders.sh — lists the PLACEHOLDER(<owner-id>) markers left in the port (owner: F1).
# Spec: ARCHITECTURE.md §11 (placeholder protocol), §12.4 (done = no markers left for your id); OWNERSHIP.md §3 F1.
#
# Usage (run from anywhere; scans mac/Sources, mac/Tests and mac/Tools, text files only):
#   Scripts/check-placeholders.sh              every marker, grouped by owner (summary first)
#   Scripts/check-placeholders.sh <owner-id>   only that owner's markers, one "path:line: text" per line —
#                                              prints NOTHING when the owner has none left (e.g. W-HIER, F2)
#   Scripts/check-placeholders.sh --summary    one line per owner: markers and files
#   Scripts/check-placeholders.sh --owners     the owner ids that still have markers, one per line
#
# Exit status: 0 = no marker listed, 1 = markers listed (or a malformed marker found), 2 = usage error.
# Also reported (stderr, and exit 1): a marker whose owner id is not a known owner, and a marker in a file that
# OWNERSHIP.md §2 gives to a different owner (the placeholder belongs to the folder owner, ARCH §11).

set -u
export LC_ALL=C

MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MAC_DIR" || exit 2

KNOWN_OWNERS="F1 F2 F3 W-SHELL W-PERSIST W-GOLD W-RICH W-CONT W-FILES W-HIER W-BUILD W-PLAN W-QUICK W-CREW W-VESSEL
W-PDF W-SIRE W-FLASH W-DRIVE"
KNOWN_OWNERS="$(echo $KNOWN_OWNERS)"

MODE=all
FILTER=""
case "${1:-}" in
    "") ;;
    --summary) MODE=summary ;;
    --owners) MODE=owners ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "check-placeholders: unknown option '$1' (see --help)" >&2; exit 2 ;;
    *)
        MODE=owner; FILTER="$1"
        case " $KNOWN_OWNERS " in
            *" $FILTER "*) ;;
            *) echo "check-placeholders: unknown owner id '$FILTER' (known: $KNOWN_OWNERS)" >&2; exit 2 ;;
        esac ;;
esac
[ $# -le 1 ] || { echo "check-placeholders: one argument at most (see --help)" >&2; exit 2; }

DIRS=""
for d in Sources Tests Tools; do [ -d "$d" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || exit 0

# One record per (marker, line): owner <TAB> path <TAB> line <TAB> text. A line naming two owners yields two.
RECORDS="$(grep -rIn --exclude='.DS_Store' 'PLACEHOLDER(' $DIRS 2>/dev/null | awk '
    {
        i = index($0, ":"); path = substr($0, 1, i - 1); rest = substr($0, i + 1)
        j = index(rest, ":"); lineno = substr(rest, 1, j - 1); text = substr(rest, j + 1)
        sub(/^[ \t]+/, "", text)
        scan = text
        while (match(scan, /PLACEHOLDER\([^)]*\)/)) {
            owner = substr(scan, RSTART + 12, RLENGTH - 13)
            if (!((path, lineno, owner) in seen)) {
                seen[path, lineno, owner] = 1
                print owner "\t" path "\t" lineno "\t" text
            }
            scan = substr(scan, RSTART + RLENGTH)
        }
    }')"

[ -n "$RECORDS" ] || exit 0

# Order owners as in OWNERSHIP.md; unknown ids last.
rank_of() {
    local i=0 o
    for o in $KNOWN_OWNERS; do
        i=$((i + 1))
        if [ "$o" = "$1" ]; then RANK=$i; return; fi
    done
    RANK=99
}
SORTED="$(printf '%s\n' "$RECORDS" | while IFS="$(printf '\t')" read -r owner path lineno text; do
    rank_of "$owner"
    printf '%02d\t%s\t%s\t%06d\t%s\n' "$RANK" "$owner" "$path" "$lineno" "$text"
done | sort -t "$(printf '\t')" -k1,1 -k3,3 -k4,4n | cut -f2-)"

STATUS=0

# Sanity: unknown owner ids, and markers in files that OWNERSHIP.md §2 gives to another owner. With an owner
# filter, only problems in that owner's files or naming that owner are reported.
FILES="$(printf '%s\n' "$SORTED" | cut -f2 | sort -u)"
OWNERS_OF="$("$MAC_DIR/Scripts/check-ownership.sh" --owner-of $FILES 2>/dev/null)"
PROBLEMS="$(awk -F'\t' -v known=" $KNOWN_OWNERS " -v filter="$FILTER" '
    NR == FNR { own[$2] = $1; next }
    {
        fowner = ($2 in own) ? own[$2] : "-"
        if (filter != "" && fowner != filter && $1 != filter) next
        if (index(known, " " $1 " ") == 0)
            printf "unknown owner id in %s:%d: PLACEHOLDER(%s)\n", $2, $3, $1
        if (fowner != $1 && fowner != "*")
            printf "%s is owned by %s but carries PLACEHOLDER(%s)\n", $2, fowner, $1
    }' <(printf '%s\n' "$OWNERS_OF") <(printf '%s\n' "$SORTED") | awk '!seen[$0]++')"
if [ -n "$PROBLEMS" ]; then
    STATUS=1
    printf '%s\n' "$PROBLEMS" | sed 's/^/check-placeholders: /' >&2
fi

case "$MODE" in
    owner)
        LINES="$(printf '%s\n' "$SORTED" | awk -F'\t' -v o="$FILTER" '$1 == o { printf "%s:%d: %s\n", $2, $3, $4 }')"
        if [ -n "$LINES" ]; then printf '%s\n' "$LINES"; STATUS=1; fi
        ;;
    owners)
        printf '%s\n' "$SORTED" | cut -f1 | awk '!seen[$0]++'
        STATUS=1
        ;;
    summary|all)
        SUMMARY="$(printf '%s\n' "$SORTED" | awk -F'\t' '
            { if (!($1 in m)) order[++k] = $1; m[$1]++; if (!(($1, $2) in f)) { f[$1, $2] = 1; nf[$1]++ }
              total++; if (!($2 in af)) { af[$2] = 1; files++ } }
            END {
                printf "PLACEHOLDER markers: %d in %d file(s), %d owner(s)\n", total, files, k
                for (i = 1; i <= k; i++) printf "  %-10s %4d marker(s) in %3d file(s)\n", order[i], m[order[i]], nf[order[i]]
            }')"
        printf '%s\n' "$SUMMARY"
        if [ "$MODE" = all ]; then
            printf '%s\n' "$SORTED" | awk -F'\t' '
                $1 != prev { printf "\n== %s\n", $1; prev = $1 }
                { printf "%s:%d: %s\n", $2, $3, $4 }'
        fi
        STATUS=1
        ;;
esac
exit $STATUS
