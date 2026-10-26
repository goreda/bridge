# fit_bench - per-phase timing harness (parallel-fitting program, piece 18)

Measures where engine run wall time goes, before and after the parallel
fitting work lands: **fitting s/glyph** (stage 1, the per-glyph capture+fit
loop), **pairs** (stage 3 spacing solve with the pair cascade + stage 4
residual kern), and **total** - per style, on the real collection (Marq +
Lÿno). `profiles` (stage 2) and `assembly` (stage 5) are recorded as context.

## Recorder (engine side)

`pipeline/src/fit_bench.rs`, enabled by one env var:

```
KNI_FIT_BENCH_OUT=/path/to/result.tsv
```

Unset = fully disabled (one relaxed atomic load per hook; no output, no
behavior change). Set = the run writes a versioned `fit_bench_v1` TSV at run
end (both ok and refused paths): phase wall intervals, one duration row per
`process_glyph` call, glyph count and cpu-sum, total wall, outcome. The
recorder is global and mutex-guarded with RAII guards at the call sites, so
the coming rayon `par_iter` per-glyph loop is measured with **no call-site
change**: per-glyph rows then carry worker-side durations and `fitting` stays
the phase wall clock, which is exactly what s/glyph means before and after.
Refuses to overwrite an existing TSV; recorder I/O failures are stderr
warnings, never run failures.

## Driver

```
run.sh <label> <engine-dir> <manifest> <workdir> [pipeline flags...]
```

Builds `kni-pipeline` (release) in `<engine-dir>` and runs one manifest with
the recorder on. Writes `<workdir>/<label>.tsv` (raw rows), `.meta` (engine
git sha, manifest sha256, flags, style id, host, thread count, rustc), plus
captured stdout/stderr. The style id is read from the manifest's own
family/subfamily rows; nothing style-specific is baked into the tooling.

## Report

```
report.py <before-dir> <after-dir> [--tsv]
```

Pairs labels across the two dirs and prints the before/after table: fitting
s/glyph, pairs s, total s, speedups, per style. Phase names are looked up in
the recorded rows; an absent phase or label reports MISSING, never zero.

## Quality domain (W13)

The same `KNI_FIT_BENCH_OUT` run also records per-glyph fit-quality rows -
the measurement domain the fit-objective work (W9) consumes. For every
fitted glyph the recorder appends `quality` rows, one per domain:

- `shipped` - the outline that lands in the font (the band-cleared outline
  fit when one exists, else the base fit);
- `measurement` - the accepted-domain drawing that profiles, spacing and
  vertical metrics are computed from (only when a separate outline fit was
  shipped).

Row shape (TSV, `fit_bench_v1`; readers must skip unknown row kinds):

```
quality  <glyph>  <domain>  <rings>  <nodes>  <fallback_line_spans>  <final_missing_extrema>  <ink_px>  <area_err_units2>
```

`area_err_units2` is `lever_api::area_error` of the drawing against the exact
source mask it was fitted on - the shared exact-coverage L1 objective vs the
threshold-128 mask that the N1 node-economy lever optimizes, in font
units^2, measured in the engine's own source frame (mask origin
`(-origin_x * scale, 0.0)`). `ink_px` is the mask's ink pixel count, so
deviation normalizes across glyph sizes. A glyph whose mask or objective
cannot be computed (dimension mismatch, invalid mask, flatten budget,
non-finite objective) is a skipped row with a stderr warning, never a run
failure. With the env var unset the quality path is the same single atomic
load as the timing path: no rows, no behavior change.

The report table compares the shipped domain across before/after: total node
count and area deviation per ink pixel, with reduction ratios. A TSV without
quality rows (a pre-W13 recorder) reports MISSING, never zero.

## Workload manifests

Two generators, both deriving everything from engine/kit sources:

- `bench_style.sh` - the real workload: the kit's maintained
  `notdef_chain.py` (cluster detect -> produce_notdef -> kit_manifest ->
  stage_notdef) prepares the style (tiles copied into a run root, .notdef
  pixel evidence staged), `run.sh` executes it. This is how the Marq + Lÿno
  numbers are produced.
- `gen_manifest.py` - a single-style full-run manifest straight from a tile
  folder (declared K from style-scales.tsv, policy + names from the engine's
  manifest-full-478.tmpl, population pin replicating the engine rule, H row
  always kept under --limit). For small synthetic workloads; full runs need
  the notdef chain.

## Before/after protocol

1. Worktree A: base ref + this patch applied; worktree B: candidate ref +
   this patch applied. (The recorder is behavior-neutral, so applying it to
   both sides keeps the measurement fair.)
2. `bench_style.sh <style-label> <engine-A> <collection> <Family/Style> <kit> <work> results/before`
3. `bench_style.sh <style-label> <engine-B> <collection> <Family/Style> <kit> <work> results/after`
4. `report.py results/before results/after`

Pin `RAYON_NUM_THREADS` across runs when comparing thread counts; the meta
sidecar records it. Compare only runs on the same host.

## Tests

- `cargo test -p kni-pipeline fit_bench` - recorder unit tests (synthetic
  clock: phase summing, re-entry order, golden TSV, interrupted-phase flag,
  cell sanitizing, empty run; quality domain: sorted/labeled render, exact
  vs shifted rectangle deviation, scale conversion, refusal paths,
  disabled no-op).
- `python3 tooling/fit_bench/test_report.py` - report pairing, speedups,
  MISSING semantics, header refusal, TSV shape.
- `python3 tooling/fit_bench/test_gen_manifest.py` - manifest generator:
  engine pin rule, template name map + uniXXXX fallback, sequence exclusion,
  --limit keeps H, whitespace/scale-missing refusals.
- `bash tooling/fit_bench/smoke_diag.sh <engine> <collection> <kit>
  [Family/Style]` - integration: one real style (default Marq/Alternate, 253
  glyphs) end to end through the notdef chain, asserts the TSV closes (all
  four phases, glyph rows cover the manifest, positive total). Takes minutes.
