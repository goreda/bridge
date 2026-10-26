#!/bin/bash
# fit_bench style driver (piece 18): prepares one collection style through the
# kit's maintained .notdef evidence chain (notdef_chain.py: detect -> produce
# -> kit_manifest -> stage_notdef, tiles COPIED into a run root so collection
# paths with spaces never reach the manifest), then runs it with the recorder
# on via run.sh.
#
# Usage:
#   bench_style.sh <label> <engine-dir> <collection-root> <Family/Style> <kit-root> <work-root> <results-dir> [lsb rsb]
#     collection-root: holds <Set>/<Family>/<Style>/glyph
#     kit-root: a kni runkit root (tools/, style-scales.tsv, style-space.tsv,
#               manifest-full-478.tmpl, style-scale-evidence/, engine -> the
#               SAME engine-dir, or a sibling it can resolve)
#     lsb rsb: post-pass offsets for the style (kit default 0 0)
set -euo pipefail
[ $# -ge 7 ] || { echo "usage: bench_style.sh <label> <engine-dir> <collection-root> <Family/Style> <kit-root> <work-root> <results-dir> [lsb rsb]" >&2; exit 2; }
LABEL="$1"; ENGINE="$2"; COLL="$3"; STYLE="$4"; KIT="$5"; WORK="$6"; RESULTS="$7"; shift 7
LSB="${1:-0}"; RSB="${2:-0}"
FAMILY="${STYLE%%/*}"; SUB="${STYLE#*/}"
STYLE_DIR=$(find "$COLL" -maxdepth 3 -type d -path "*/$FAMILY/$SUB" | head -1)
[ -n "$STYLE_DIR" ] || { echo "bench_style: no style dir for $STYLE under $COLL" >&2; exit 2; }

R="$WORK/R/$FAMILY/$SUB"
rm -rf "$WORK/R"
python3 "$KIT/tools/notdef_chain.py" --style-dir "$STYLE_DIR" --style "$STYLE" \
  --run-root "$R" --engine "$ENGINE" --tools "$KIT/tools" \
  --template "$KIT/manifest-full-478.tmpl" --scales "$KIT/style-scales.tsv" \
  --space-table "$KIT/style-space.tsv" --lsb-add "$LSB" --rsb-add "$RSB" \
  --post-scope base --post-scope-label post-lsb-rsb-pass

# PN-3 kit hardening: --fallback-export-warn removed. A style whose typed
# fallback ledger is non-empty now HARD-FAILS the export here instead of
# shipping a warn-tagged OTF; the delivery gate (delivery_gate.py) also
# refuses any font carrying the FALLBACK-EXPORT-WARNING nameID 10 tag.
bash "$(cd "$(dirname "$0")" && pwd)/run.sh" "$LABEL" "$ENGINE" "$R/manifest.txt" "$RESULTS" \
  --allow-partial
