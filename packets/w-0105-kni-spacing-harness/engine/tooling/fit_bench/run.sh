#!/bin/bash
# fit_bench run driver (parallel-fitting program, piece 18).
# Builds the engine in ENGINE_DIR (release) and runs ONE manifest with the
# fit_bench recorder enabled, storing the raw TSV plus a meta sidecar in
# WORKDIR. Nothing style-specific is baked in: the style id is read from the
# manifest's own family/subfamily rows, flags come from the caller.
#
# Usage:
#   run.sh <label> <engine-dir> <manifest> <workdir> [pipeline flags...]
# Example (full-set route, same flags as the run kit):
#   run.sh marq-alternate /path/to/engine manifest-run-local.txt results \
#       --diagnostic-test-export --allow-partial
set -euo pipefail
[ $# -ge 4 ] || { echo "usage: run.sh <label> <engine-dir> <manifest> <workdir> [flags...]" >&2; exit 2; }
LABEL="$1"; ENGINE="$2"; MANIFEST="$3"; WORKDIR="$4"; shift 4

field() { awk -v k="$1" '$1 == k { $1=""; sub(/^ /, ""); print; exit }' "$MANIFEST"; }
FAMILY="$(field family)"; SUBFAMILY="$(field subfamily)"
[ -n "$FAMILY" ] && [ -n "$SUBFAMILY" ] || { echo "run.sh: manifest lacks family/subfamily rows" >&2; exit 2; }
# style id: the repo's one slug rule (tools/test_e2e_style_chain.sh): NFKD
# ASCII fold, spaces stripped, '/' -> '-'. "Marq/Alternate" -> Marq-Alternate,
# "Lÿno/Stan" -> Lyno-Stan.
STYLE_ID="$(python3 -c 'import sys, unicodedata; s = sys.argv[1]; print(unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().replace(" ", "").replace("/", "-"))' "$FAMILY/$SUBFAMILY")"

mkdir -p "$WORKDIR"
OUT="$WORKDIR/out-$LABEL"
TSV="$WORKDIR/$LABEL.tsv"
META="$WORKDIR/$LABEL.meta"
rm -rf "$OUT"; rm -f "$TSV"

( cd "$ENGINE" && cargo build --release -p kni-pipeline )
BIN="$ENGINE/target/release/kni-pipeline"
[ -x "$BIN" ] || { echo "run.sh: build produced no binary at $BIN" >&2; exit 1; }

START=$(date +%s)
( cd "$ENGINE" && KNI_FIT_BENCH_OUT="$TSV" "$BIN" "$MANIFEST" "$OUT" --style-id "$STYLE_ID" "$@" ) \
    > "$WORKDIR/$LABEL.stdout" 2> "$WORKDIR/$LABEL.stderr" || true
END=$(date +%s)

SHA() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi }
{
  echo "label	$LABEL"
  echo "style_id	$STYLE_ID"
  echo "engine_git_sha	$(git -C "$ENGINE" rev-parse HEAD)"
  echo "manifest_sha256	$(SHA "$MANIFEST")"
  echo "flags	$*"
  echo "wall_s	$((END - START))"
  echo "host	$(uname -srm)"
  echo "nproc	$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
  echo "rayon_num_threads	${RAYON_NUM_THREADS:-default}"
  echo "rustc	$(rustc --version)"
  echo "date	$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$META"

[ -f "$TSV" ] || { echo "run.sh: recorder wrote no TSV at $TSV (see $LABEL.stderr)" >&2; exit 1; }
echo "fit_bench: $LABEL -> $TSV"
