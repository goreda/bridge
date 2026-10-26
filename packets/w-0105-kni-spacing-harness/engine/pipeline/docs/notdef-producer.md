# Pixel-source .notdef producer

The normal path uses captured pixels. It does not need an original font, cmap,
maxp, a source-font SHA or a claim that a requested codepoint is unsupported.
The validator owns `PixelNotdefKind`, `PixelContext` and the
`pixel_form_sha256` form-hash definition. The producer imports the shared
types and emits evidence v3 only.

## Claim-only scope

The producer does bounded reads, byte pins and evidence packaging. It never
decodes images, never counts form frequency and never compares gray pixels.
Kind, selected source, per-tile roles and `pixel_form_sha256` are claims; the
validator verifies them against decoded pixels (form hash, all-255 blank ink,
frequency). This keeps detection cheap: hash count and winner selection happen
once, in the validator, with no extra gate before a candidate is flagged.

## Input and decisions

Each source is an ordinary tile or a claimed candidate (repeated-form or blank
cell). Source CPs are nonzero Unicode scalars. Every tile has a
capture-relative whitespace-free path and an exact byte SHA. A duplicate CP, a
path/SHA conflict, an empty or oversized file, a bad capture-record pin or a
broken context refuses.

A candidate claim needs at least two claimed tiles of one kind: a repeated
form, never a singleton. No claim or a single claim refuses as
`MissingPixelEvidence`. Mixed repeated-form and blank-cell claims refuse as
`AmbiguousPixelCandidate`. The selected source is the claimed tile whose byte
SHA equals the request's `selected_source_sha256`; a mismatch refuses.
`pixel_form_sha256` is the winning-form hash claim, shape-checked as 64
lowercase hex and emitted verbatim. Non-claimed tiles, including losing or
competing forms, are validated and pinned in the request but are not listed in
the evidence; they are not errors.

The winner group is the extraction manifest, as in the old codebase: these
codepoints are not written into the font as characters. They are extracted,
and their shared form is emitted only at gid0 as `.notdef`.

A blank-cell claim carries no numeric advance and no space binding. The blank
gid0 advance is the advance of the font's widest character, bound later in
assembly; the space character keeps its own narrow advance. There is no 700,
image-width, zero-advance or other fallback. The `space_evidence_sha256` field
is refused for both kinds. The blank role label is a claim; the validator
verifies the all-255 decoded pixels.

## Runtime interface

```
produce_notdef PIXEL_REQUEST.tsv TILE_ROOT NEW_OUTPUT_DIR MAX_INPUT_BYTES MAX_PIXELS MAX_WORKING_BYTES
```

The example target is a capture/evidence producer, not a font export. The
output directory must not exist. A write failure removes only that newly
created output. Source inputs are read-only. Source paths cannot escape the
canonical root, including through symlinks. Reads check metadata and remaining
capacity before allocation and detect a length change during the read.

The TSV below shows literal `\t` for tabs:

```
kni-pixel-notdef-request\tv3
style\tFamily/Style
cohort\tFamily/Style
frame\tEXACT_CAPTURE_FRAME
scale\tEXACT_K
ink_model\tdecoded-gray-all-255-no-transform-v1
selected_source_sha256\tSELECTED_CANDIDATE_SOURCE_SHA256
pixel_form_sha256\tWINNING_FORM_SHA256
request_source\tCAPTURE_LEDGER_REFERENCE
capture_record\tcapture-ledger.bin
capture_record_sha256\tCAPTURE_LEDGER_SHA256
source\t0x41\tglyph/a.png\tTILE_SHA256\tordinary
source\t0x100\tnotdef/b.png\tTILE_SHA256\trepeated-form
source\t0x101\tnotdef/c.png\tTILE_SHA256\trepeated-form
```

For a blank cell, claim role `blank-cell` on at least two tiles. Do not add a
numeric advance or a space-evidence field. The source capture record is pinned provenance, not an authenticated author or
a hidden source-font check. The consumer still has to bind it to its capture
run.

Evidence v3 has `kind`, `style`, `frame`, `scale`, `ink_model`,
`capture_sha256`, the singleton `pixel_form_sha256` claim, `selected` path and
byte SHA, and `pixel_source` CP, role, path and byte-SHA rows for the
winner-group tiles only. It has no dimensions,
requested_unsupported, missingchar, verdict or numeric advance fields. The
validator decodes and checks dimensions and pixels directly.

Output: evidence.tsv, the original request, source-capture-record.bin and
byte-identical relative source copies. There is no capture-manifest v1 and no
separate audit file. The evidence capture field pins the independent source
capture record.

Limits bound source bytes and retained payload. They are not an allocator/RSS
guarantee.

## Handoff and validation scope

The kit supplies the request from its collection and capture records, including
the claims; users do not need to construct a TSV. Shared validator and kit
writers own consumer routing and relocation. Old proof-based fixture
constructors are not compatible with this API. Legacy v2, if retained by the
validator, is a separate reader and never a prerequisite for v3.

Development checks are compilation and synthetic unit tests only. No production
pipeline, fitting, collection, kit launch or export is run by this change.
A helper and a unit test do not establish full kit-to-engine acceptance.
