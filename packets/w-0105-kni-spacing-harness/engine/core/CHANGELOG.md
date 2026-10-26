# kni-core changelog

## S10 (2026-10-23) - gate measured frame clearing on closed-ring evidence

Measure keeps its default routing and existing per-edge 1/2-fill measurement,
but clears only a joint four-edge closed ring with a proven inner boundary.
Edge-flush letterform stems and solid tight crops are preserved. Per-tile
FrameBandEvidence records the discriminator, rejected band and cleared ring
count. SeparatePresentRing behavior, scale, baseline and fit policy are unchanged.


## 0.1.5 (2026-10-18) - node/segment economy, review revisions 4+5

Revision 4 replaces the proposed 0.1.2 tradeoff with a no-regression gate.

### Node economy and quality contract

The node pass still uses the outward-rounded interval Hausdorff bracket
introduced in 0.1.1/0.1.2, but a rendered-output guard now runs after the
lever. The guard rasterizes input and output under the curve_stress proof
semantics (pixel-centre sampling, nonzero winding, source ink = gray < 128)
and compares tile IoU by exact integer cross-multiplication. There is no
float tolerance. If the output ratio is lower, the whole node-pass output
is replaced by the exact input and the report carries
`raster_iou_guard=reverted`. This does not special-case any glyph,
language, style, or fixture; independently valid removals whose rendered
IoU does not regress remain available.

Measured result: the six-glyph curve_stress baseline now matches the
committed file byte for byte, including 00C9_scan at 25 nodes, IoU
0.9646414887794198, fit SHA 46b1be5590f8c9b7..., and overlay SHA
152d7172c90fecff.... The 0.1.2 one-node economy gain on that glyph is not
claimed. This revision earns certified rejection of unsound proposals and
keeps the independent synthetic economy cases, not measured corpus node
gain.

### Arithmetic and accounting

All interval primitives validate ordered finite operands and results.
All derived coordinate differences use interval subtraction. The parameter
margin is f64::EPSILON (2^-52), conservatively above the parameter
division rounding error. Work accounting now charges every completed pair
evaluation even when a later arithmetic operation in the same bracket
round fails; the candidate-cache builders surface a failure immediately
instead of storing it and evaluating later candidates.

The declared resource conventions remain 2^18 pair-distance evaluations
per candidate and 2^24 across all candidates/rings/removal rounds of one
lever run. The base round costs 2*49*49 = 4802 actual evaluations. These
cap bracket pair work only, not total wall time or the rest of the lever
pipeline. Exhaustion returns Indeterminate.

The cubic merge Gram solve no longer uses the pre-existing absolute
1e-12/1e-300 determinant cutoff. The terms are unitless; the new
scale-aware acceptance compares det/(c00*c11) with a conservative
conditioning margin derived from the number of accumulated samples and
binary64 unit roundoff. This is a refusal heuristic, not a certified
round-off bound; below it the chord/3 fallback is kept.

### Warning-clean overlay (separately attributed)

A minimum warning-clean overlay removes the 29 pre-existing diagnostics
without weakening assertions: three tests now import the public modules
instead of duplicating source files into second test crates, unused
imports are removed, one unused private capture helper is removed, and the
W7 test's intentionally unread diagnostic fields/values are underscored.
The two boundary test binaries no longer execute four duplicate copies of
module-internal tests; those tests still run in the library target.

### Linux evidence

- Library: 453 passed, 0 failed.
- All 75 integration targets: 503 passed, 0 failed.
- Doc tests: 0.
- Complete deduplicated suite total: 956 passed, 0 failed, 2 ignored.
- `cargo check -p kni-core --lib --tests --message-format=short`: zero
  warning diagnostics. Raw before/after warning logs are in logs/.
- `cargo test -p kni-core --test curve_stress baseline_corpus_matches_committed`:
  passed; the committed baseline was not modified or blessed.
- Debug boundary exhaustion: 66.173609 ms,
  260568 pair evaluations. Release lever timings are in
  logs/bench-before3.tsv and logs/bench-r4.tsv. Timing evidence is
  single-host/single-run and not a real-time bound.

### Remaining scope note

The raster guard compares rendered tile IoU. It does not claim a global
symbolic bound on cumulative curve deviation; per-candidate interval
brackets and the rendered-output no-regression gate are separate checks.

### Review revision 5: wording and determinant margin

Relabels the Gram determinant acceptance as a scale-aware conditioning
heuristic, not a certified round-off bound. The code behavior and numeric
margin are unchanged from 0.1.3; the comment no longer claims that the
sample/unit-roundoff formula proves determinant dependence. Corrects the
suite accounting wording: the two non-run tests are ignored, not filtered.


## 0.1.4 (2026-10-18) - item 12: cohort-vs-canonical per-class regression report

- Added core/src/regress_class.rs: cohort-vs-canonical-run per-class regression report (sign test, no cutoff, typed unmatched rows).
- Added core/examples/regress_class_report.rs (CLI, all inputs explicit).
- Added core/tests/regress_class.rs and fixture tests/fixtures/regress-class/cohort-w2-8.tsv (34 regressed + 2 neutral rows, historical locator).
- No engine behavior change.

## 0.1.3 (2026-10-18) - item 2: post-fit duplicate cleanup + pipeline warning cleanup
Note: item 3 took 0.1.1, item 4 took 0.1.2; this round takes 0.1.3 (slide confirmed by main 16:33).
- pipeline/src/main.rs: after drop_constant_cubics in the export stage, every glyph outline goes through
  duplicate_point_audit::tidy_duplicate_points. Removes only zero-length lines and fully collapsed cubics
  (exact binary64 equality, no tolerance, no per-language/glyph/style code). Ledger rows `tidy` and
  `tidy-summary` per glyph are appended to the run receipt. Non-finite coordinates refuse the run.
- pipeline warning cleanup (4 files, no allow): dead measured_space() helper + unused import in main.rs
  tests, needless mut in bound_detector_validator/profiles_par, unused binding in stem_pair_containment_tests.
- No change to duplicate_point_audit.rs or svg_outline.rs (already implemented at HEAD).
