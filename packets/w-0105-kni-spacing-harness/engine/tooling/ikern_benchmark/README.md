# Isolated iKern benchmark

Experiment only. No production defaults or pipeline source files are changed.

Dependencies: Python 3.10+, fontTools, uharfbuzz; Rust workspace toolchain.

```
cargo build --release -p kni-metrics --example ikern_benchmark
python3 tooling/ikern_benchmark/benchmark.py \
  --reference IMFeENrm28P.ttf --engine target/release/examples/ikern_benchmark \
  --out new-experiment --anchor To \
  --words AVATAR Typography Hamburgefontsiv WA Yo rr \
  --row-step 16 --jobs 8
cd tooling/ikern_benchmark && python3 -m unittest -v
```

Reference SHA256 must equal
`fe9705bbde51af802719246d4608d08d37bde956ab99d9a590da996a5221a24c`.
Its name table explicitly attributes spacing and kerning to iKern. The
reference is not accepted based only on its family name. Obtain its license
from the upstream Google Fonts IM Fell English distribution.

The adapter zeroes original LSB/RSB/advance padding and removes all source
kerning tables before any geometry enters Rust. Composite glyphs are decomposed
before changing coordinate systems. Empty-outline advances are zeroed too.
Rust receives only UPM, glyph identity and flattened outline coordinates. It
calls the existing KNI profile, spacing and residual export APIs, with no
reference metrics/context injected into the solver.

The explicit post-spacing calibration is a uniform integer advance delta:
`round((reference_anchor_width - raw_KNI_anchor_width)/anchor_glyph_count)`.
LSB receives floor(delta/2). Kerns are not changed. This is calibration,
not a quality score, and often cannot achieve exact equality due to integer
advance quantization. Exit 0 means the anchor-width tolerance matched, not
that KNI is better. Exit 3 means anchor calibration missed tolerance. Exit 2
means an input, policy, engine, geometry or export refusal. A partial experiment
directory can remain after refusal; no report.json means no completed result.

The anchor is training data. Other requested words are explicitly held out.
Their widths and errors are reported without refitting. Pair adjustment errors
are measured with actual HarfBuzz shaping over pairs drawn from the evaluation
characters. Differences from iKern are not optical-quality scores. No metric
here establishes a winner. Ligatures and contextual alternates are off for
this pair-fitting experiment, kern is on. No horizontal scaling is used.

Full-font is the default population: all inked outlines, including unmapped
ones, enter the solver. Empty outlines cannot be profiled and remain listed
in exclusions. `--characters` is an explicitly scoped bounded experiment,
not a substitute for the full-font run; the population is recorded in the
receipt. Engine holds, rejections and fallback candidates are counted. Only
ready pairs are exported; fallback candidates are not silently accepted.
Flattening tolerance is explicit. Metrics-frame comparison allows at most
2*tolerance+1e-5 font units for bounded flattened-vs-analytic extrema error.
The writer rounds to integer units and records the calibration delta.

## Measured checkpoint, 23 Oct 2026

Full pinned font: 372 source glyphs, 369 inked glyphs processed, 3 empty
outlines excluded. row_step=16, flatten=0.25, lambda=0, dcap=auto, jobs=8.
114862 ready pairs, zero holds/rejections, solver complete for the declared
population. To calibrated to 2411 vs 2412 units with +412 advance delta.
Held-out width errors: AVATAR +484, Typography +1937, Hamburgefontsiv +3670,
WA -188, Yo +67, rr +304. These are differences, not a quality verdict.
Mean absolute pair-adjustment difference over 576 evaluation pairs: 129.0955.

A higher-resolution row_step=4 full-font attempt timed out at 100 seconds.
It was not passed. A separate explicitly scoped 52-letter row_step=4 run
completed; its calibration and held-out results must not be confused with
the full-font checkpoint. Production pipeline export, final-font audit and
optical whole-word judgement remain independent work. This harness is a
measured checkpoint, not closure of the user's larger iKern objective.
