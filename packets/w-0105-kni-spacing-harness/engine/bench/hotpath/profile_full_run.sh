#!/bin/bash
# profile_full_run.sh - SPEED-2 orchestrator (new bench file, additive).
# 1) REPEATS timed runs of the full 478-glyph Marq/Alternate manifest
#    (last run sampled at HZ) -> results/stage_times.tsv + results/samples.tsv
# 2) symbolize + stage/crate fold -> results/hotpath_by_stage_crate.tsv
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$(cd "$HERE/../.." && pwd)"
KIT="$(cd "$ENGINE/.." && pwd)"
BIN="$ENGINE/target/release/kni-pipeline"
TILEDIR="${TILEDIR:-$KIT/tiles}"
RESULTS="$HERE/results"
HZ=99
REPEATS="${REPEATS:-3}"

[ -x "$BIN" ] || { echo "build first: cargo build --release -p kni-pipeline"; exit 1; }
[ -x "$HERE/rip_sampler" ] || rustc -O -o "$HERE/rip_sampler" "$HERE/rip_sampler.rs"
mkdir -p "$RESULTS"

# Manifest via the repo's own generator (tooling/fit_bench/gen_manifest.py):
# binds capture_cohort + capture_frame + declared scale row, replicates the
# engine's population pin. The raw tmpl alone misses rows the parser requires.
SCALES="$KIT/kit-config/style-scales.tsv"
python3 "$ENGINE/tooling/fit_bench/gen_manifest.py" \
  --tiledir "$TILEDIR" --style "Marq/Alternate" \
  --template "$ENGINE/manifest-full-478.tmpl" --scales "$SCALES" \
  --out "$RESULTS/manifest-run-local.txt"
FAM=$(grep -m1 '^family ' "$RESULTS/manifest-run-local.txt" | sed 's/^family //')
SUB=$(grep -m1 '^subfamily ' "$RESULTS/manifest-run-local.txt" | sed 's/^subfamily //')
STYLE_ID="$(printf '%s/%s' "$FAM" "$SUB" | tr -d ' ' | tr '/' '-')"
FLAGS="--diagnostic-test-export --allow-partial --style-id $STYLE_ID"

echo "== 1/2: $REPEATS timed runs (last one sampled at ${HZ} Hz) =="
rm -f "$RESULTS/stage_times.tsv" "$RESULTS/samples.tsv"
python3 "$HERE/run_timed.py" "$BIN" "$RESULTS/manifest-run-local.txt" \
  "$ENGINE/out-hotpath" "$REPEATS" "$RESULTS/stage_times.tsv" \
  --sampler "$HERE/rip_sampler" "$HZ" "$RESULTS/samples.tsv" -- $FLAGS \
  | tee "$RESULTS/stage_summary.txt"

echo "== 2/2: symbolize + fold (stage windows of the sampled run = last run_idx) =="
python3 "$HERE/symbolize_merge.py" "$BIN" "$RESULTS/samples.tsv" \
  "$RESULTS/stage_times.tsv" "$REPEATS" "$RESULTS/hotpath_by_stage_crate.tsv"
echo "done: $RESULTS"
