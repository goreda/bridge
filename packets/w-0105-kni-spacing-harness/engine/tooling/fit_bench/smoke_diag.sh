#!/bin/bash
# fit_bench integration test (piece 18): runs ONE real collection style
# (default Marq/Alternate, 253 glyphs) end to end through the kit's notdef
# evidence chain with the recorder enabled, and asserts the TSV closes.
# Takes minutes on a small machine - this is the piece's integration proof,
# not a unit test. Unit-fast coverage: cargo test fit_bench + test_report.py
# + test_gen_manifest.py.
# Usage: smoke_diag.sh <engine-dir> <collection-root> <kit-root> [Family/Style]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${1:?engine dir}"; COLL="${2:?collection root}"; KIT="${3:?kit root}"; STYLE="${4:-Marq/Alternate}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
bash "$HERE/bench_style.sh" smoke "$ENGINE" "$COLL" "$STYLE" "$KIT" "$WORK" "$WORK" 25 25 >/dev/null
TSV="$WORK/smoke.tsv"
fail() { echo "smoke: FAIL: $1" >&2; exit 1; }
head -1 "$TSV" | grep -qx "fit_bench_v1" || fail "bad header"
grep -qx "outcome	ok" "$TSV" || fail "outcome != ok (run stderr in results dir)"
for ph in fitting profiles pairs assembly; do
  grep -q "^phase	$ph	" "$TSV" || fail "no $ph phase row"
done
N_MANIFEST=$(grep -c '^glyph ' "$WORK/R/${STYLE}/manifest.txt")
N_TSV=$(grep -c '^glyph	' "$TSV")
[ "$N_TSV" -ge "$N_MANIFEST" ] || fail "glyph rows $N_TSV < manifest glyph rows $N_MANIFEST"
T=$(awk -F'\t' '$1=="total_s"{print $2}' "$TSV")
awk -v t="$T" 'BEGIN{exit !(t>0)}' || fail "total_s not positive"
echo "smoke: OK ($STYLE, $N_TSV glyph rows, total ${T}s)"
