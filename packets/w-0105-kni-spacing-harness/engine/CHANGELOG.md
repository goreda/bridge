261023-184800-k5-k6-scoped-b-port (candidate)
- Scope: per-pair export-gate closure accounting (items fail, batches do not; default mode never refuses), exact not-approved receipt carrier with process exit 3, final-publish provenance bound to the real bytes of the run.
- Provenance: KNI_SOURCE_COMMIT (verified, runtime input) turns the sidecar on; unset = typed provenance_unavailable degrade, no invented commit; any KNI_CLAIMED_* without it refuses before publication. Generated master output hash/name binds from the mandatory publish payload, DISTINCT from the master-source input pin (None on B).
- Evidence: library + real-binary tests in the S1d delivery; full-suite status per W5. Population-floor and stage1_only paths ship no sidecar (open provenance coverage gaps, named).

261023-184000-native-master-companion-restoration (candidate)
- Scope: mandatory editable native .glyphs companion for current pipeline; no K4 input-guidance or spacing algorithm changes.
- Change: restore historical structural decomposition/writer modules additively; read final CFF/hmtx/OS2/GPOS bytes; preserve named editable paths, metrics, advances and effective kerning. Publish master with OTF in exclusive rollback set even when optional measurement hook refuses. RUN renames both outputs together; ALL-STYLES and adapter flag missing companions; kit builder checks native source and consumer.
- Evidence: bounded real Mercator and Marq Alternate H/h/n/o native runs with six glyphs each; exact width, metric and final-GPOS gates pass. Scope/test limits in accompanying W2 evidence report. No kit release is claimed.
- Custody: current f3837c6f source plus historical scv8 master modules, isolated W2 patch for chief integration.

# KNI engine changelog

## Record scope and provenance

Prepared 2026-10-18 from the repository's existing root `CHANGELOG.md`
and live engine manifests and source reads. This engine-local file is a
version index and a source-labeled reconstruction, not a replacement for
root serial history. It does not change a Cargo version or declare a release.

The supplied integration export baseline is `38f506e3` (short commit,
integrator-attested). Live reads did not return a commit SHA. Their content
hashes below identify the exact read material, but do not prove an atomic
HEAD snapshot. Before landing, compare every manifest and the root changelog
to the selected full commit and refresh this record if they differ.

Source classes:
- **Manifest read:** current version bytes read directly from the repository.
- **Root history:** recorded serial entries, not a new execution or an
  independent re-run of their tests.
- **Source read:** bounded current API/source description, not release history.
- **Pending:** assigned work or a proposed target. No implementation,
  measurement, version bump or landing is implied.

Root history source: repository-root `CHANGELOG.md`, SHA256
`d9c87b097a772383734420d1d176332ae449a3c4bf95f270ac435a523b01c2dc`. The root file remains the detailed serial record.
All paths below are relative to `kni-kit/out8-runkit-v2/engine/` unless stated
otherwise. Versions are crate versions, not kit serials or drawing-standard
versions. A standard named v0.2 does not mean the master crate is 0.2.0.

## Current crate-version index

| Crate | Manifest version | Manifest path | SHA256 of read bytes |
| --- | --- | --- | --- |
| kni-core | 0.1.0 | `core/Cargo.toml` | `9566c6d25e85e4cbb26e950eaf8346f5f9f15109ed07d7492f3b5c739bd5a032` |
| kni-geometry-prototypes | 0.1.0 | `geometry-prototypes/Cargo.toml` | `3785f347395b0e1532f07b4f54029e7973168406efdec1fee45a4bebead72bf3` |
| kni-guide-binding | 0.1.0 | `guide-binding/Cargo.toml` | `58516e4b9fc131167a98b7b6aa53dd70fce0a25e6afbc9d5dc4fd99ca1d4cba8` |
| kni-learning | 0.1.0 | `learning/Cargo.toml` | `ac5364f16edbfe626689cb51c2fde124cde53ecf8183ccd77d2530f9063ff837` |
| kni-master | 0.1.0 | `master/Cargo.toml` | `0bd1c81c460821e363c1afc7ec3cfa932a887487e7ec388736a802431e05c7fe` |
| kni-metrics | 0.1.1 | `metrics/Cargo.toml` | `4cfd3d695d418f5b512d4c30abe2e759e392a1783c117474a605ecb86e5a37f3` |
| kni-pipeline | 0.1.1 | `pipeline/Cargo.toml` | `2ecc4214be598a2ea2908a138dcba46cdafba41fd9797619ac04e7c06cb0863e` |

Workspace membership is not the same as this index: the read workspace
`Cargo.toml` lists core, metrics, learning and pipeline only. Geometry,
guide binding and master have separate manifests; their inclusion here
is not a claim that a workspace test exercised them.

## Recorded changes by crate version

These are the seven observed crate-version entries. Where the introduction
commit or previous version is not established, that gap is explicit. Later
serial changes under the same crate version are not invented patch releases.

### kni-core 0.1.0

- Scope: fitting, capture and outline support, plus the later master-fit
  context/trace/binding and span-ledger additions recorded below.
- Change vs previous version: initial-version predecessor and release date
  are not established by the inspected sources. Changes within 0.1.0 are
  recorded by serial, not by a claimed 0.0.x comparison.
- Root history: `261018-011500` economy objective; `261018-020000` economy
  search; `261018-035600` duplicate tidy; `261018-044200` canonical reconcile;
  `261018-114407`, `123606`, `125357`, `134249` master-fit instrumentation,
  binding, bound wrapper and identity-only span ledger. The latest entry
  explicitly retains crate version 0.1.0.
- Evidence: see the source-preserving serial extracts below. The latest
  root entry records full core results 933 -> 941 passed, zero failures,
  two ignored and 97 inherited warning lines. This is root-history evidence,
  not a fresh execution here and not a warning-free claim.
- Custody: manifests and root history read; no code mutation in this record.

### kni-geometry-prototypes 0.1.0

- Scope: geometry-only training prototypes; classifications remain proposed.
- Change vs previous version: introduction commit, release date and a
  previous-version delta are not established by the inspected history.
- Source read: `geometry-prototypes/src/lib.rs` exposes geometry, fitting,
  candidate/cluster/assignment artifacts and geometry pins. This is a source
  description, not a statement that a model was trained or approved.
- Evidence: source SHA256 `a68f3695f70abe7e3fb233ee4e1450529a305244c2e2f8e9c68a6a9f37cfdac1` plus the manifest pin above.
- Custody: read only; no test or release assertion is added.

### kni-guide-binding 0.1.0

- Scope: source-class-bound guide measurements and annotations.
- Change vs previous version: introduction commit, release date and a
  previous-version delta are not established by the inspected history.
- Source read: `guide-binding/src/guide_binding.rs` declares measurement/
  annotation only, with no snap, geometry mutation or auto-classification.
- Evidence: source SHA256 `3fe412464c0cdee20c047161ae5d7a587a25212147ccfb81a0a88965a98fa0e0` plus the manifest pin above.
- Custody: read only; no production guide-binding activation is asserted.

### kni-learning 0.1.0

- Scope: an add-only, pinned, schema-checked learning store.
- Change vs previous version: introduction commit, release date and a
  previous-version delta are not established by the inspected history.
- Source read: `learning/src/lib.rs` describes feature-key outcome
  distributions and a cold fallback for absent, empty or invalid stores.
  This description does not establish a training run or trained weights.
- Evidence: source SHA256 `51b73496f73ac18fb0b58102a1abc97a589226ace0d440461c9bc2d18d2e8577` plus the manifest pin above.
- Custody: read only; no store or model artifact is created by this entry.

### kni-master 0.1.0

- Scope: master-mode outline model, drawing-standard checkers and export
  support. The observed manifest remains 0.1.0.
- Change vs previous version: introduction commit, release date and a
  previous-version delta are not established by the inspected history.
- Source read: `master/src/lib.rs` names model/check/validate/raster/vector/
  OTF and vector-row modules. Its own introductory comment calls export
  merge a future slice; this record does not turn that comment into a
  current implementation verdict without checking the implementation.
- Evidence: source SHA256 `d960319748cccfd410140180b4b5b5aad472dc6bb8d77d720a490853ed8c15be` plus the manifest pin above.
- Custody: read only. Target 0.2.0 is pending below, not this release.

### kni-metrics 0.1.1

- Scope: spacing, kerning, class and anchor audit work recorded in root
  serial history; consumes the learning crate.
- Change vs previous version: current 0.1.1 is manifest-verified; the exact
  0.1.0 -> 0.1.1 version-bump commit and complete boundary diff are not
  established. Do not equate the canonical-working kit serial with a
  proven crate bump.
- Root history: `261017-134636` anchor-audit detector; `261017-143002`
  outline-spacing determinism; `261017-145501` refusal ordering;
  `261017-232000` negative-origin compensation; `261017-234000` kern
  guard-input revert; `261018-013000` default-off class-spacing and
  direction-symmetry lanes; `261018-035700` audit-path closure.
- Evidence: root history is the attributed evidence for these changes.
  Default-off or measurement-only entries are not relabeled active.
- Custody: read only; no new kern quality or timing claim.

### kni-pipeline 0.1.1

- Scope: engine orchestration with core/metrics and bounded parallelism.
- Change vs previous version: current 0.1.1 is manifest-verified; the exact
  0.1.0 -> 0.1.1 version-bump commit and complete boundary diff are not
  established by these reads.
- Root history: `261017-050000` explicit spacing-pair cascade pool;
  `261017-053300` default-off OOHH spacing guard; `261017-234000` removal
  of the regression-producing guard inputs; `261018-035700` audit wiring;
  `261018-044200` canonical reconciliation reuse. The last moved
  `rounding_reconcile.rs` from pipeline into core, leaving a pipeline import.
- Evidence: root serial history; no new pipeline execution is claimed.
- Custody: read only; no source, Cargo or lock changes in this record.

## Unreleased: parallel engine work

All sections below are pending review and measured current-tree discovery.
They are not releases, completed work or proof of twelve remaining defects.
An already-landed repair must be verified and reused, not written again.
Each implementation landing must add its actual before/after behavior,
source and test pins, true command exits, version decision and custody to
its section. Document-only and test-only activity does not manufacture a
code-release entry. Keep the root serial record in sync at code landing.

### Pending team 01: node and segment economy

- Scope: current objective/search path, preserving fit and shape quality.
- Locations: core/src/economy.rs, economy_eval.rs, fit_objective.rs,
  node_objective.rs, fit_search.rs and fitter_requirements.rs.
- Base: selected current full commit required; historical economy serials
  above are evidence, not a start-branch instruction.
- Version: no bump assigned here. Changes/results: not yet reviewed.

### Pending team 02: post-fit duplicate cleanup

- Scope: current emit-time duplicate behavior and regression coverage.
- Locations: core/src/svg_outline.rs, duplicate_point_audit.rs and
  core/tests/duplicate_point_tidy.rs.
- Base: current full commit required; reuse the recorded 035600 tidy API.
- Version: no bump assigned. Results: not yet reviewed; historical 155/39
  counts are not current measurements.

### Pending team 03: integer zero-length lines; proposed core 0.1.1

- Scope: post-rounding zero-length spans/lines and typed preservation.
- Location: core/src/rounding_reconcile.rs; pipeline imports the core module.
- Base: current full commit required; coordinate with canonical-path work.
- Version: 0.1.1 is a proposed target for kni-core, not a landed version.
  Cargo/lock and compatibility changes must be part of the reviewed patch.
- Changes/results: implementation and before/after evidence pending.

### Pending team 04: canonical capture-to-charstring path

- Scope: capture_png -> fit_captured -> integer-charstring consistency.
- Locations: core/examples/canonical_path_run.rs, core/src/capture.rs,
  capture_fit.rs and rounding_reconcile.rs, with pipeline import boundary.
- Base: current full commit required; recorded 044200 repair already exists.
- Version: no bump assigned. Results: not yet reviewed; no production
  behavior change is inferred from a canonical measurement-arm change.

### Pending team 05: four-way benchmark

- Scope: same-population KNI/potrace/autotrace/vtracer comparison.
- Locations: existing benchmark harness and evidence paths to be pinned
  by the team before execution; no guessed path is treated as current.
- Version: measurement only unless a separately reviewed code fix is needed.
- Results: current run not yet reviewed; preserve tool versions and arms.

### Pending team 06: missing Turkish glyph coverage

- Scope: current source/cmap/capture/export coverage and missing identities.
- Locations: current mapping and export paths to be pinned by the team.
- Version: no bump assigned. Results: current missing set not yet established;
  earlier glyph repairs must not be reported missing again.

### Pending team 07: kerning and spacing classes

- Scope: class-level held-out behavior against the kern=0 control.
- Locations: metrics class/spacing implementation; confirmed regression
  target metrics/tests/kern_scope_guard.rs; exact solver paths pending pin.
- Version: no bump assigned. Results: not yet reviewed. No per-pair patch
  substitutes for a measured class-level cause.

### Pending team 08: master regression; proposed master 0.2.0

- Scope: remaining generator/compatibility work on the master foundations,
  without reopening closed verification or completed analysis runs.
- Locations: master/ and the relevant core master-fit modules, pinned by team.
- Version: 0.2.0 is a proposed target for kni-master, not a landed version.
- Changes/results: implementation, compatibility contract, Cargo/lock
  changes and measured regression evidence pending review.

### Pending team 09: hardcoded-constant audit

- Scope: font-derived thresholds, named algorithm constants and declared
  implementation conventions, without blind numeric replacement.
- Locations: tooling/literal-inventory-ledger.tsv and
  docs/w2-5-literal-inventory.md plus the pinned consumers.
- Version: no bump assigned. Results: current inventory not yet reviewed.

### Pending team 10: audit path

- Scope: current typed audit closure and remaining consumer coverage.
- Locations: core/src/outline_interface.rs, metrics/src/anchor_audit.rs,
  metrics/examples/anchor_audit.rs, core/tests/encode_closure_audit.rs and
  pipeline/src/main.rs. Reuse the recorded 035700 implementation.
- Version: no bump assigned. Results: remaining gaps not yet reviewed.

### Pending team 11: full-cmap rendering delivery gate

- Scope: complete glyph sweep and evidence pack at delivery.
- Locations: existing export/render/format harnesses to be pinned by team.
- Version: no bump assigned. Results: current coverage not yet reviewed.
  This is engine-list item 11, not the separate OCR arbitration item 11.

### Pending team 12: historical regressing-glyph class analysis

- Scope: source-grounded serif/terminal classification and a matched current
  canonical-arm check. Historical cohort size 34 is not a fresh failure count.
- Source locator: docs/evidence/2026-10-13-engine-diff-run/;
  diff-metrics.tsv SHA256
  b2d3d0358b50583aeece878f7d262220a98ff377a3f852466642fc76e6b79b2b;
  diff-summary.json SHA256
  e63ec200991907068b360b65be6770356d6ae1d5b968c5a87e5cbd8d259cf55a.
- Limit: the derived class-table report recovered values from a transcript,
  with rounded precision. Original metric bytes must be recovered before
  a precise baseline claim. The historical old box-fit preview-font arm and
  new fixed-K=1.71 trace arm are not a matched canonical comparison.
- Version: analysis only unless a separate code fix is reviewed.
- Results: current class analysis not yet reviewed.

## Source-preserving root-history extracts

The following entries are copied from the inspected root history without
recomputing tests or treating internal approval language as new authority.
They preserve attribution and limits. Other serials remain in the root file.

### Root serial: 261018-134249-kni-core-master-fit-span-ledger

- Scope: kni-kit/out8-runkit-v2/engine/core/src/master_fit_span_ledger.rs
  (new), kni-kit/out8-runkit-v2/engine/core/src/lib.rs, and
  kni-kit/out8-runkit-v2/engine/core/tests/master_fit_trace_binding.rs
  only. Adds the identity-only span-ledger formatter module; lib.rs
  registers it; the trace-binding test file is replaced in full. No
  Cargo manifest or lock changes; no other code; no OCR-lane files.
- Change vs previous serial: full kni-core suite 933 -> 941 (+8: the
  span-ledger tests sl_p01_ellipse_exact_golden_and_layout,
  sl_p02_ellipse_excludes_receipt_policy_axes_and_pin,
  sl_p03_notch_chains_and_wrapped_interval_as_supplied,
  sl_p04_tworing_order_and_record_sequence,
  sl_p05_hostile_ids_escape_exactly,
  sl_p06_escape_injective_and_literal_passthrough, sl_p07_determinism,
  sl_p08_actual_output_claim_labels).
- Evidence: Landing2 owning-tree runs on parent 4e28526d, cargo and rustc
  1.99.1 (isolated scratch toolchain), one cold target dir per side,
  --locked (workspace Cargo.lock 98431ef2, core Cargo.lock 90a972e8,
  both unchanged): baseline 933 pass / 0 fail / 2 ignored over 77
  summaries, exit 0 (log sha256
  d6784e80f5d6cfeec17796d567f9e647e0b40d0c4569616f7176bbad84b93d84);
  candidate 941 pass / 0 fail / 2 ignored over 77 summaries, exit 0
  (log sha256 da46a7708ded6617d7934c65a0a320e063f7042e2c10de5433e0b0a56d765b82).
  97 inherited warning lines in each run; not warning-free. Landed bytes:
  module sha256 13f49d26afdda5c94cf7275373eddc74db8fdce8724de50b9805154436b59a4d,
  lib.rs sha256 a49d5e249c1ac2825f1b56dffae515becda629cd64e800a9d6098b5f6abe1c5a,
  tests sha256 23b380b11caeda8d9c23eb9f94886dac349216d00e4c3a60f28b86a52b957fe1.
- Custody: candidate bundle (zip sha256
  96174a013900d8bc0ac92016cac04f4a230b69b813c5625d1730f772fb158900)
  staged via bridge, per-file hashes verified; Landing2 executed the
  owning-tree runs and lands. Crate version remains 0.1.0; version
  record is this serial entry.

### Root serial: 261018-044200-kni-canon-fix-1-canonical-reconcile

- Scope: close the W2-3 canonical-chain refusal gap (base 5bcdd587 + land
  series 31). engine/core/src/rounding_reconcile.rs (moved from
  engine/pipeline/src/), engine/pipeline/src/main.rs (import),
  engine/core/src/lib.rs (module), engine/core/examples/
  canonical_path_run.rs (canonical arm wiring),
  engine/core/tests/canonical_reconcile.rs (5 new tests),
  docs/engine/execution/20261018-canon-fix-1/. No production-path behavior
  change; canonical arm only.
- Root cause (measured, structural): the reconcile stage landed as a module
  private to the kni-pipeline binary; the canonical harness lives in
  kni-core examples and could not import it, so the canonical arm fed raw
  fit output (non-integer coordinates) straight to the integer charstring
  gate. 7 glyphs production ships refused with
  charstring_refused:UnrepresentableCoordinate.
- Change: rounding_reconcile moved into kni-core byte-identical (crate
  paths only) so both the production binary and the canonical harness wire
  the same landed code; additive quantize_outline + QuantizeReport (the
  same per-scalar export-grid rounding production applies in
  prepare_generated_with_placement, typed stats, non-finite left for the
  gate); canonical arm runs quantize -> drop_constant_cubics between fit
  and charstring and measures the reconciled outline; production arm
  untouched (raw chain as W2-3 measured it).
- Evidence: BEFORE (in-tree, measurements.run2 W2-3): canonical refusals 7
  (percent, comma, exclamdown, quotesinglbase, quotedblbase, perthousand,
  uni2078), canonical K1 IoU mean 0.985097. AFTER (writer run, this tree,
  same 253 sha-verified tiles): canonical refusals 0 (all 253 glyphs reach an integer charstring; canonical-k1.otf notdef + 253 glyphs, sha256 fc2a23608ad1852006f15c5649ba787e818ba2ca9604a01aa8a9e9f80c40711e), K1 IoU
  mean 0.985087 mean (delta -0.00001); production arm byte-identical to W2-3 (sha256 661fbf5a90de9cca2c951d2cf44f7afaacde3d1db20d5e592039a6d35303d1d5). Tests: workspace 1972 passed / 0 failed baseline
  -> 1977 passed / 0 failed (5 new); cargo check
  0 warnings.
- Efficacy: the canonical chain now reaches an integer charstring on every
  glyph production ships; every reconcile effect is a typed ledger/note row
  (reconcile_quantized, constant_cubic_dropped/held); nothing drops
  silently.
- Custody: writer-run on base 5bcdd587 + series 31; patch applies with
  patch -p1 from repo root; forward-only.

### Root serial: 261018-035700-kni-w2-6-audit-path

- Scope: audit path completion (October 13 item 10): the run's typed audit
  chain now closes at the encode boundary. Touched: metrics/src/anchor_audit.rs,
  core/src/outline_interface.rs, core/tests/encode_closure_audit.rs (new),
  metrics/examples/anchor_audit.rs, pipeline/src/main.rs (wiring only, see
  Custody). core/src/line_audit.rs is unchanged: its stage-1 wiring was
  already complete (line-audit.tsv on every live full/stage1_only run).
- Change:
  1. Kern stage: the hold-reason audit (HoldReasonSummary /
     audit_hold_reasons / render_hold_summary_tsv) is wired into the run.
     anchor_audit gains a total typed classifier (classify_hold_note)
     covering the four declared OverlapHold producers in
     generated_outline_kern (collision at exact solver placement, solver
     wall_gap disagree, no verified safe integer distance,
     containment_compensation_negative_origin) plus an Unclassified class
     that keeps any future producer visible instead of breaking the run.
     HoldReasonSummary gains negative_origin and unclassified, both counted
     in held(): no held pair is invisible. The summary is built from the
     kern buckets themselves (kern.ready / fallback_ready / overlap_holds),
     never by re-parsing text. New always-written artifacts
     kern-hold-summary.tsv and kern-hold-flags.tsv; the declared-override
     (kern not run) path writes typed not_run markers, never a false clean.
     Receipt gains kern_hold_audit ran/flags/pairs/held and
     kern_hold_audit_flag rows, mirroring the anchor_audit pattern.
  2. Encode boundary: outline_interface gains the closure audit
     (audit_glyph_closure / closure_audit_tsv). Every glyph handed to the
     encoder is validated through the library's own closure adapter
     (ValidatedClosedGeometry::validate; the invariant is shared, not
     copied) and emits a typed row: glyph, rings, spans, status
     (closed | open_contour | non_finite | no_outline). Detection only: the
     encoder's own gates stay the only behavior gate. New always-written
     artifact encode-closure-audit.tsv; receipt gains one
     encode_closure_audit ran/glyphs/closed/not_closed row.
  3. metrics/examples/anchor_audit.rs: the post-hoc classifier now
     delegates to the library's classify_hold_note. Fixes two latent bugs:
     its "no_safe_integer" prefix never matched the real note ("no verified
     safe integer distance near"), and the negative-origin hold class was
     uncovered (hard error on such ledgers).
- Evidence (writer-run, this patch):
  cargo test --workspace --lib --tests --examples: 1969 passed, 0 failed
  (pristine base 5bcdd587: 1959 passed, 0 failed; +10 new tests: 5
  anchor_audit hold-taxonomy tests, 5 encode_closure_audit tests).
  cargo check --workspace --release: 0 warnings, exit 0.
  End-to-end audit chain (diag6 manifest, --diagnostic-test-export
  --allow-partial --style-id KNIDiagnostic-SixGlyph): line-audit.tsv
  (stage 1) -> anchor-audit-signs.tsv / anchor-audit-flags.tsv (solve) ->
  kern-hold-summary.tsv / kern-hold-flags.tsv (kern; pairs 30, ready 30,
  held 0, hold_rate 0.000000) -> encode-closure-audit.tsv (encode;
  glyphs 7, closed 6, not_closed 1). The not_closed row is the blank-arm
  .notdef (rings 0, spans 0, no_outline): intentional-empty, detection row
  only; the encoder accepts it exactly as before.
  Bit-identity on out-of-scope paths (pristine vs patched, same flags):
  font-KNIDiagnostic-SixGlyph.otf sha256
  f3715dd0df3bb4a9a1a8c82dbf9d084e22761b23ba8803ef26c1b2ea07723894
  identical (3192 bytes); kern-ledger.tsv, kern-diagnostic.tsv,
  spacing.tsv, mapping.tsv, spacing-pair-ledger.tsv,
  spacing-hold-reasons.txt, rounding-ledger.txt, line-audit.tsv,
  anchor-audit-*.tsv, fallback-glyphs.tsv, profile-metadata.tsv all
  byte-identical. stage1-cache.txt differs only in engine_exe_sha256 (the
  binary changed - the cache carries the binary hash by design);
  receipt/run-provenance differ only in the new typed rows and the
  environmental out_dir path (and run_config_sha256, which binds the
  out_dir path).
- Efficacy: the audit chain is now observable end to end with typed rows;
  no behavior change to shipped bytes (OTF hash identical above). No claim
  on kern/spacing outcomes.
- Custody: pipeline/src/main.rs touch is wiring-only and flagged per brief:
  three insertion sites (hold-audit compute + receipt rows at the kern
  receipt block, closure-audit collect + receipt row after approved_base,
  three artifact writes in the final artifact block). No solver, guard,
  export, or cache-byte-stream change. Known boundary, pre-existing:
  line-audit.tsv is live-route only; a stage1-cache replay run does not
  re-emit it (the audit did not run on that route). Left as-is: persisting
  it would touch the cache byte stream, which is out of scope.

- Integrator note: one main.rs hunk (encode-boundary closure audit) rebased past slot 23's drop_constant_cubics callsite - both insert at the same point after prepare_generated; audit now runs after the cubic cleanup, so it sees the exact glyphs handed to the encoder. Writer patch otherwise verbatim; slot sha above covers the rebased file.

================================================================

### Root serial: 261018-035600-kni-w2-1-duplicate-tidy

- Scope: W2-1 post-fit duplicate cleanup (development list #2). engine/core/src/duplicate_point_audit.rs, engine/core/src/svg_outline.rs, engine/core/tests/duplicate_point_tidy.rs, engine/core/examples/duplicate_tidy_stage1.rs. main.rs and the pipeline crate untouched; OTF path untouched.
- Change: tidy_duplicate_points removes only provably geometry-preserving duplicates (zero-length Line spans, fully degenerate Cubics) with one typed ledger row per removal; rings that would empty are kept and reported. outline_svg_tidy emit variant; outline_svg byte contract untouched.
- Evidence: writer-run: kni-core baseline 809/0, patched 817/0 (8 new tests); 0 warnings. Re-measurement on stage1-cache shipped rings (real scans): diag6 10 pairs/6 glyphs (all explicit closure); paulnew 2030 pairs/132 glyphs; provably redundant spans found: 0. The historical 155/39 figure (Oct-13 item 2) is not reproducible at this snapshot; its source document is absent from the tarball. OTF bit-identical pristine vs patched (diag6 font sha256 f3715dd0df3bb4a9a1a8c82dbf9d084e22761b23ba8803ef26c1b2ea07723894).
- Efficacy: removable duplicate spans 0 before -> 0 after on measurable populations (typed-remainder acceptance branch); cleanup machinery proven on synthetic unit tests and ready at the emit point; no silent drops.
- Custody: patch sha256 71b6114483e676bb8de3ed9d6519d8c180c8745c7f325e7a3be41b3eb6dc7f6c from writer W2-1 via main; forward-only. Unverified remainder: the 155/39 source population (font/style unknown) - rerun duplicate_tidy_stage1 on a Marq full-run stage1-cache if one becomes available.

Group 9: W2-6 audit path, W2-4 four-way benchmark

### Root serial: 261018-013000-kni-nv2-class-spacing-units-direction-symmetry

- Scope: metrics self_anchored_spacing NV-2 lanes (work list 2026-10-16 items 2+3+7): direction-symmetric keep/drop and class spacing units with typed spacing-emission rows. Frozen SpacingPolicy/SpacingSolution field sets, pipeline wiring and every other crate path unchanged (bit-identical); both lanes default-off.
- Change: new ClassHarmonyPolicy gate + solve_spacing_with_class_harmony entry point returning a ClassHarmonyReport (symmetry promotions, per-class unit rows with all three candidates and scores, per-pair spacing adjustments); below-epsilon directions whose reverse was emitted ship their verified solve; class units selected from mean/median/midrange by the declared data rule (non-uniform = |gap-unit| >= the solver's own residual epsilon; score = total deviation of non-uniform pairs / class pair count; ties mean -> median -> midrange); harmonization emitted as spacing, never kern. kern-scope-literals fixture registers the three new 2.0 halves (count 25 -> 28).
- Evidence: patch sha256 64d8b65891e083bffca24efb403f34819e2ffb5c2383232aea5a83072950e5ce; writer-run kni-metrics 514/0/2 ignored (6 new nv2 tests); check 0 warnings; integrator re-check: kni-metrics 514/0, all 6 nv2 tests green, 0 warnings. Evidence run (synthetic probed population, both lanes on): 44 symmetry promotions == the frozen asymmetric set exactly, accounting closed; 6 class unit rows (straight->straight selects median 27.3519 by measured score); 139 typed ClassSpacingAdjustment rows; kern/glyph output byte-identical to frozen.
- Efficacy: on the probed synthetic population the work-list asymmetry case is fully promoted and straight->straight selects the median unit by measured score; no efficacy claim on shipped fonts until the full Marq Alternate replay (pinned spacing-pair-ledger 167a08eb, w1-draft snapshot caveat on record).
- Custody: patch from the NV-2 writer via main; review and land by the chief architect; forward-only.

### Root serial: 261018-020000-kni-ne2-economy-search

- Scope: NE-2 economy search (owner economy directive; NE-1 integration). core/src/fit_search.rs, core/src/fitter_requirements.rs, core/src/capture.rs, core/src/capture_fit.rs, core/src/node_objective.rs, core/src/fit_objective.rs (NE-1 test-helper alignment), docs/kni/2026-10-18-ne2-economy-search-conventions.md. Consumes NE-1's EconomyObjective through the W10 FitObjective interface; REQUIRES the NE-1 land directly before it.
- Change: corner screen, collinear merge, C->L degrade and tidy with derived thresholds (no free constants; provenance in the conventions doc); typed EconomyLedger; fit_run_search_economy_reported entry point. capture.rs/capture_fit.rs/node_objective.rs hunks are warning cleanups only. Closed gate (FIT_SEARCH off) bit-identical to the incumbent path.
- Evidence: writer-run on 5bcdd587 + NE-1: kni-core 826/0, kni-metrics 508/0, kni-pipeline 538/0, learning 40/0, workspace release 1912/0, check 0 warnings; the 4 integrator-flagged test-cfg warnings fixed (base-inherited remainder 101 -> 97). Integrator re-check on the combined tree: kni-core 826/0, workspace check 0 warnings, closed-gate bit-identity tests green.
- Efficacy: the economy objective now drives a real search path with typed ledger receipts; shipped bytes unchanged at the closed gate (bit-identity pinned by test). The Mona/Paul New segment+IoU table is measurable once the fitter lane runs the open gate.
- Custody: patch sha256 705f565eb6aef7039549dcad78f25d8194d03fd1307173de92962f4d41139d7d from writer NE-2 via main; forward-only. Follow-up: NE-2 writer to reproduce uni2075 (SUP-1 tile) on the next run and report whether the root is fit_search or capture_fit/closed_fit.

### Root serial: 261018-011500-kni-ne1-economy-objective

- Scope: NE-1 node-economy objective (owner directive 2026-10-13 12:15 +03 via main). core/src/economy.rs, core/src/fit_objective.rs, core/tests/economy.rs, docs/kni/2026-10-18-economy-objective-conventions.md. Excluded: fitter wiring (fit_search gate, capture_fit, cubic_fit are other lanes); no production-path change.
- Change: additive (patch 362 lines). (1) EconomyObjective implements the W10 FitObjective contract using the module's existing band^2 currency (fidelity + curvature + node price from the candidate's own spans_used; single-span totals bit-identical to Objective::score). (2) accept_refit carries the economy-aware refit accept rule: strict error reduction (incumbent branch, budget-free) OR strict segment reduction with error <= the existing budget (exact equality accepts); every other shape rejects, non-finite/negative inputs reject. (3) DECLARED_CONVENTION ECONOMY_IOU_LOSS_GATE = 0.002 (per-glyph tile-IoU loss gate, exact-loss boundary pinned by test), provenance doc in docs/kni/.
- Evidence: writer-run on base 5bcdd587: kni-core 818/0 (baseline 809, +9 new); workspace release 1904/0; cargo check workspace release = 0 warnings. Integrator re-check on the applied tree: kni-core lib 411/0, tests/economy 22/22. Open-gate search driven end to end by EconomyObjective (2 candidates, finite selected score, Fitted outcome).
- Efficacy: the fitter now has a real economy objective and the economy-aware accept rule as tested, callable APIs; no shipped-byte change until the fitter lane wires them. The Mona + Paul New before/after segment+IoU table is a post-wiring measurement (NE-2 integration).
- Custody: patch sha256 3d0d0eaf5e9d5c474e755b4623ddb55ce985f005b55b9c77060ff732f0d084ac from writer NE-1 via main; forward-only.

### Root serial: 261017-234000-kni-kern-guard-input-revert
- Scope: the two guard inputs the bisect pinned as the v11.3 -> v11.4 kern regression (first-bad b4dd2d19): the ink_containment post-solve wiring (pipeline/src/main.rs) and the Lane D optical-centre split in the sidebearing solve (metrics/src/self_anchored_spacing.rs). Guard decision code untouched; all other paths unchanged.
- Change: pure ablation, +37/-116 across 3 files. ink_containment stage wiring removed (module remains, unwired); sidebearings return to the flat band-row mean of clamped depths; kern-scope-literals.tsv ledger counts updated for the removed Lane D uses (26 -> 24 and 26 -> 25); kni-metrics fixtures re-derived against the flat-mean model with full derivations in test comments.
- Evidence: bisect closed first-bad b4dd2d19 (overlap_hold 0 -> 52,158; f-v +123 -> -87.4, v-c +22.96 -> -174.75, y-o -171.9, v-o -174.06). After this revert, 478-tile probe: overlap_hold 0, f-v +123, v-c +24, y-o +22, v-o +24 (all four at their v11.3 values); 6 pairs with |delta| > 20u vs v11.3. Writer-run suites: kni-metrics 508 passed / 0 failed, kni-pipeline 529 passed / 0 failed.
- Efficacy: closes the kern-hold regression at its measured inputs; v11.3 kern quality restored with guard decisions unchanged.
- Custody: patch sha256 b3415ec2ceb52da8c7670be0846bb71e78bad873755d5f8f9c6f8e0a67ac19f7 from writer via the parent agent; integrator review passed (clean apply, ledger maintained, minimal diff); forward-only.

