#!/bin/sh
# ledger_gate.sh - one-command gate wrapper for ledger_check.py.
#
# Usage:
#   ledger_gate.sh [ledger_check flags] FILE...
#   ledger_gate.sh [ledger_check flags] --files-from MANIFEST
#   ledger_gate.sh [ledger_check flags] --pre-ship OUT_DIR
#
# FILE args or MANIFEST (one path per line) name the ledger/receipt files
# the lane's diff emits or changes. --pre-ship discovers every *.txt and
# *.tsv under OUT_DIR recursively (a full engine run output) and gates
# them all (zip/transit junk is filtered: __MACOSX dirs and AppleDouble
# ._* files never reach the checker). The checker's scope rules check
# typed ledgers and receipts,
# skip known columnar tables and run artifacts, and fail closed on any
# new file kind. This is the single-command entry for the CI/pre-ship
# flow (the kit pre-ship step runs it after FORMAT-PASS and VERIFY, once
# per style output dir or once over the whole output tree).
# Flags pass through to ledger_check.py
# (--strict-legacy/--strict-variants, --allow-unregistered).
# Prints one summary line per file, violation details, and a GATE footer;
# exit code is ledger_check.py's (0 pass, 1 violations, 2 usage/io error),
# so the per-diff gate can wire `tools/conc/ledger_gate.sh <files>` directly.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

FLAGS=""
FILES_FROM=""
PRESHIP=""
for a in "$@"; do
    case "$a" in
        --files-from) FILES_FROM="__next__" ;;
        --pre-ship) PRESHIP="__next__" ;;
        --*) FLAGS="$FLAGS $(printf '%s' "$a" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")" ;;
        *) break ;;
    esac
    shift
done
if [ "$FILES_FROM" = "__next__" ]; then
    [ $# -ge 1 ] || { echo "ledger_gate: --files-from needs a manifest path" >&2; exit 2; }
    MANIFEST=$1; shift
    [ $# -eq 0 ] || { echo "ledger_gate: no FILE args after --files-from MANIFEST" >&2; exit 2; }
    [ -f "$MANIFEST" ] || { echo "ledger_gate: manifest not found: $MANIFEST" >&2; exit 2; }
    set --
    while IFS= read -r line; do
        [ -n "$line" ] && set -- "$@" "$line"
    done < "$MANIFEST"
fi
if [ "$PRESHIP" = "__next__" ]; then
    [ $# -ge 1 ] || { echo "ledger_gate: --pre-ship needs an output dir" >&2; exit 2; }
    OUT_DIR=$1; shift
    [ $# -eq 0 ] || { echo "ledger_gate: no FILE args after --pre-ship DIR" >&2; exit 2; }
    [ -d "$OUT_DIR" ] || { echo "ledger_gate: output dir not found: $OUT_DIR" >&2; exit 2; }
    PRESHIP_LIST=$(mktemp "${TMPDIR:-/tmp}/ledger_gate_preship.XXXXXX")
    trap 'rm -f "$PRESHIP_LIST"' EXIT
    find "$OUT_DIR" -type f \( -name '*.txt' -o -name '*.tsv' \) \
        -not -path '*/__MACOSX/*' -not -name '._*' | LC_ALL=C sort > "$PRESHIP_LIST"
    [ -s "$PRESHIP_LIST" ] || { echo "ledger_gate: no *.txt/*.tsv files under $OUT_DIR" >&2; exit 2; }
    set --
    while IFS= read -r line; do
        [ -n "$line" ] && set -- "$@" "$line"
    done < "$PRESHIP_LIST"
    echo "ledger_gate: pre-ship discovery found $# file(s) under $OUT_DIR"
fi
[ $# -ge 1 ] || { echo "usage: ledger_gate.sh [--strict-legacy|--allow-unregistered] FILE... | --files-from MANIFEST | --pre-ship OUT_DIR" >&2; exit 2; }

JSON_FILE=$(mktemp "${TMPDIR:-/tmp}/ledger_gate.XXXXXX")
if [ "${PRESHIP_LIST:-}" ]; then
    trap 'rm -f "$JSON_FILE" "$PRESHIP_LIST"' EXIT
else
    trap 'rm -f "$JSON_FILE"' EXIT
fi
# shellcheck disable=SC2086,SC2090
eval "python3 \"\$HERE/ledger_check.py\" --json $FLAGS \"\$@\"" > "$JSON_FILE" 2>&1
rc=$?
if [ $rc -eq 2 ]; then
    cat "$JSON_FILE" >&2
    exit 2
fi
FLAGS="$FLAGS" python3 - "$JSON_FILE" <<'PYEOF'
import json, os, sys
doc = json.load(open(sys.argv[1]))
tot = {"files": 0, "total": 0, "ok": 0, "summary": 0, "variant": 0,
       "blank": 0, "vio": 0}
for r in doc["results"]:
    if "skipped" in r:
        print("%s: SKIPPED (%s)" % (r["file"], r["skipped"]))
        continue
    tot["files"] += 1
    nv = len(r["violations"])
    for k in ("total", "ok", "summary", "variant", "blank"):
        tot[k] += r[k]
    tot["vio"] += nv
    print("%s: %d lines - %d ok, %d summary, %d variant, %d blank, %d violation(s)"
          % (r["file"], r["total"], r["ok"], r["summary"], r["variant"],
             r["blank"], nv))
    for v in r["violations"][:20]:
        print("  line %s: %s%s" % (v["line"] if v["line"] is not None else "-",
                                   v["class"],
                                   (": " + v["content"]) if v["content"] else ""))
    if nv > 20:
        print("  ... %d more violation(s) (run ledger_check.py for the full list)" % (nv - 20))
strict = "--strict-legacy" in os.environ.get("FLAGS", "") or "--strict-variants" in os.environ.get("FLAGS", "")
bad = tot["vio"] + (tot["variant"] if strict else 0)
print("GATE %s: %d file(s), %d line(s) - %d ok, %d summary, %d variant, %d blank, %d violation(s)%s"
      % ("FAIL" if bad else "PASS", tot["files"], tot["total"], tot["ok"],
         tot["summary"], tot["variant"], tot["blank"], tot["vio"],
         " (variants counted, strict mode)" if strict and bad else ""))
PYEOF
exit $rc
