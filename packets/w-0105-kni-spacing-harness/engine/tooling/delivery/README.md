# Source-bound delivery gate

`delivery_gate.py --font FONT --manifest MANIFEST --vector-receipt VECTOR_RECEIPT --reference-font-sha256 SHA --output EVIDENCE_DIR --ppem PPEM --threshold THRESHOLD`

The gate is fail-closed. Call it from the real production delivery entrypoint.
Code existing in the repository is not proof that the entrypoint uses it. The wrapper requires a hash-bound vector-fidelity receipt for the complete cmap.
The reference font hash is the exact source outline font assessed by that receipt;
the delivered font hash is independently bound by the ordinary delivery manifest.

Dependencies: Python 3, fontTools, Pillow. CFF1 final fonts only.
PPEM and binarization threshold are caller-bound render-contract inputs, not font heuristics.

Manifest fields:
- `source_revision`, `source_identity` (family/style), `font_sha256`, `required_codepoints`
- `glyphs`: every cmap mapping, exactly once; codepoint (integer or U+hex)
- each glyph: `capture` (path relative to manifest, sha256, status ink or
  intentional_blank, source reason for blank, same source_identity, synthetic=false, role=glyph); `fit` (engine_revision,
  path, parameters, frame, measurement); `capture_audit` (path, sha256);
  `charstring_sha256`.
- Fit path must be `capture_png>fit_captured>integer_charstring`.
- Fit parameters/frame/measurement must match the capture-audit artifact,
  whose `charstring_hex` must equal the final compiled CFF charstring bytes.

`cargo run --example capture_audit -- TILE OUT RDP_EPS SCALE SQUARED_ERROR MAX_REFITS ADVANCE TX TY`
records pre-integer outlines, explicit quantization/frame, measurements and
Type2 bytes. Source PNG and engine revision must be hash/revision pinned by
the manifest producer. Do not manufacture historical audit records for W2.

`capture_coverage.py --manifest M --output O` plans missing source captures.
Declared coverage requirements travel only through the general
`required_codepoints` list: one rule set for every language, no per-language
code. A manifest carrying the removed language-specific `require_turkish`
field is rejected fail-closed so a stale manifest never silently loses a
requirement it still declares. Unicode decomposition is reference
metadata, not authority to construct outlines. Missing/blank source capture
is a coverage blocker, never permission to invent a glyph.

Numerical PASS emits individual cmap PNGs, a sweep sheet, audit.json,
gate.json and SHA256SUMS.json. It does not authorize delivery.
Review actual pixels before making visual-review JSON: reviewer, status
APPROVED, font_sha256, gate_sha256, images (every PNG filename and sha256).
The seal verifies all hashes and that complete hash-bound review before
writing delivery-ready.json. A missing/stale/incomplete review is a failure.

Tests: `python3 -m unittest discover -s tests -v`.
`tests/test_full_cmap_render_sweep.py` is the permanent full-cmap render
delivery gate: it sweeps a complete cmap (contiguous Unicode blocks, several
hundred codepoints) through the production entrypoint with the compiled
`capture_audit` binary, real per-glyph source tiles, real fit audits, honest
outline measurements and the mandatory render sweep, evidence pack and seal.
It needs the compiled Rust binary (`cargo build --example capture_audit`)
and skips with instructions when the binary is absent. A source-bound run
against real collection captures remains required on integration.

`build_delivery_manifest.py --font F --intake I --engine-revision REV --output M`
binds the canonical build's audit JSONs to the final font and creates the
manifest consumed by the gate. Intake has source_revision/source_identity,
explicit required_codepoints (empty unless supplied), and glyphs with codepoint/capture/capture_audit. Both source
and audit hashes must already be supplied by the source intake/build. The
producer refuses absent audits, wrong source bytes, changed final Type2 bytes,
and incomplete cmap. It does not fabricate audits for previously spliced fonts.

## Vector-fidelity delivery receipt

`vector_gate.py --receipt R --reference-font-sha256 SHA --codepoints U+XXXX,...`
validates the required source-bound vector receipt. The receipt schema is
`kni.vector-delivery-gate.v1` (JSON Schema: `vector-gate-receipt.schema.json`)
and contains `source_font_sha256`, `status`, one
`glyphs` row per source cmap codepoint, and `table_rows`. Each glyph row and every
table row carries `path_label: "vector"`. Each codepoint has exactly two metric
rows: `symmetric_difference_area` in `unit^2` and `hausdorff` in `units`.

A row passes only when symmetric-difference area is at most its reported
`area_floor`, and Hausdorff distance is at most its reported `distance_floor`.
The summary metrics/floors must match the table rows; all values and limits must
be finite and nonnegative. Duplicate, missing, extra, unlabelled, hash-mismatched,
or failed rows block delivery. The receipt is copied into the evidence pack and
hash-bound by `SHA256SUMS.json`. Its source-font pin must identify the reference
font used for the vector comparison, not the output candidate.

Each glyph audit record also carries a structured `audit_path` object with the
source tile and hash, fit parameters, frame, measured fit results, capture-audit
reference, and final charstring hash. The referenced audit file must use the
`kni.capture-audit.v1` schema and contain the source bytes, path, parameters,
frame, measurement, and encoded charstring.

## Full-cmap vector receipt preparation

The permanent full-cmap render sweep test
(`tests/test_full_cmap_render_sweep.py`) runs the producer against a complete
render sweep of a generated reference font, with measurements taken from real
compiled-binary fits; the remaining synthetic-only producer tests stay as
unit coverage. A sweep against real collection captures remains required on
integration.

Before a render sweep, create an input manifest from the source font's measured
cmap. `vector-input-manifest.template.json` is a placeholder template, not a
ready-to-run manifest; its placeholder hash and example codepoint must be replaced from the current font inventory before use. Its JSON Schema is `vector-input-manifest.schema.json`.
Replace the reference-font digest with the SHA-256 of the exact font whose vector
outlines are being measured and enumerate every codepoint in its cmap exactly
once. Do not copy a codepoint count or font digest from a prior run.

The independent cmap interface is a versioned JSON document with `schema:
"kni.measured-cmap.v1"` and the codepoint list returned by reading the pinned
source font. It must be supplied to the producer; no cmap count is inferred from
the measurements.

The measurement interface is a versioned JSON document with `schema:
"kni.vector-measurements.v1"`, `reference_font_sha256`, and `glyphs`. Each glyph
entry contains `codepoint`, `path_label: "vector"`,
`symmetric_difference_area`, `area_floor`, `hausdorff`, and `distance_floor`.
Values and limits are supplied by the trusted vector measurement stage; the
producer does not render, calculate geometry, choose thresholds, or invent
missing measurements.

`vector_receipt_producer.py --manifest INPUT --measurements MEASUREMENTS --output
RECEIPT --measured-cmap CMAP` validates exact codepoint coverage against the
independently read source cmap, the font-hash binding, path labels,
finite nonnegative measurements and limits, then emits deterministic receipt
rows for both required metrics. A measured value passes when it is less than or
equal to its corresponding reported floor. Any row over its limit makes the
receipt status `FAIL`; invalid or incomplete inputs are rejected without writing
a receipt. Run only after the full-cmap source measurements exist. This
preparation step does not execute the sweep.

Tests for the producer use synthetic measurements only:
`python3 -m unittest discover -s tests -p 'test_vector_receipt_producer.py' -v`.

## Canonical batch production entrypoint

`canonical_delivery.py --plan P --audit-binary B --output O --ppem N --threshold T`
executes the compiled capture_audit binary on every ink-mapped glyph, replaces
CFF charstrings in a hash-pinned baseline font, builds the bound manifest, and
runs the mandatory full-cmap sweep. Other font tables remain from the baseline.
The result is NUMERIC_CANDIDATE_VISUAL_PENDING, never delivery-ready. After
actual pixel review, seal the unchanged evidence pack with seal_evidence.py;
do not rerun the build to apply a review of an earlier font.

Plan: base_font {path, sha256}, vector_receipt {path, sha256}, audit_binary_sha256, engine_revision,
source_revision, source_identity,
required_codepoints, and glyphs covering the base cmap exactly. Each glyph has
codepoint, capture (path/hash/identity/status/reason/synthetic=false/role=glyph),
and fit.parameters {rdp_eps,squared_error,max_refits}, fit.frame
{scale,translation:[tx,ty]}. These parameters and placements must be measured
and bound by the caller. Advance is read from the baseline hmtx. Intentional
blank sources require their explicit canonical capture_audit {path,sha256}.
The entrypoint refuses incomplete plans, wrong-style sources, synthetic inputs,
missing audits and changed hashes. It does not add missing glyphs. GID0 is
preserved from the hash-pinned baseline and lies outside the cmap sweep.

## Explicit preserved baseline path

A glyph without a source tile may use `provenance: unchanged_baseline` only
with `preserved_baseline`: path, full font sha256, source_identity,
source_available=false, reason, status (ink or intentional_blank), and full
charstring_sha256. The gate independently reads baseline and final font,
requires identical codepoint-to-glyph name, Type2 bytes, Private dict,
local/global subrs, UPM and advance/LSB. This is a disclosed pass-through,
not a captured-source or newly fitted glyph. The audit records the source
limitation. Changed glyphs cannot enter this path. No missing cmap is deleted.

Charstring binding. The font writer may re-encode numbers in a charstring
(for example a 16-bit integer operand stored as a one-byte operand) without
changing the drawing program. The audit is therefore bound to the final font
by comparing the decoded charstring programs (operators and operands); the
final charstring byte hash is recorded separately in the manifest and checked
by the gate. A different operator or operand fails the comparison.
