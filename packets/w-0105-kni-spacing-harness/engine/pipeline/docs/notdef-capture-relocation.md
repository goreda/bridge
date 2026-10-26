# .notdef capture-root and relocation contract

This documents the existing engine contract. It does not relax containment.

`R` is the parent directory of the actual main manifest passed to the engine.
Main uses it as the parser base and as `RunConfig.capture_dir`. Moving only the
main manifest to `out/run-*` does not move its capture root to the kit directory.
Use a separate bundle directory for R and a new, nonexistent output directory.

All glyph sources, independent capture manifest, .notdef evidence record,
selected tile and witness tiles must resolve canonically under R. Relative paths
must not contain `..`; symlinks resolving outside R are rejected. Use copied,
byte-identical regular files in the bundle rather than external collection paths.

Path bases differ:

| Row | Path base |
| --- | --- |
| Main `glyph`, `capture_manifest`, `notdef evidence` | R |
| Capture manifest `source` | R, NOT the capture manifest's parent |
| Evidence `selected` and `witness` | Evidence record's own parent |

Recommended layout: main manifest, capture.tsv, evidence.tsv, and tiles/ all
under R; put evidence.tsv at R to avoid needing parent traversal. Main glyph
paths and capture source paths then both use `tiles/name.png`; evidence tile
paths use the same `tiles/name.png` spelling. Inventory binds each codepoint to
the canonical tile path and its SHA256. Supported glyph rows and all selected/
witness tiles must match that inventory. Witness codepoints must match as well.
Do not fabricate or change witness classifications during relocation.

When paths inside capture/evidence text change, update pins in this order:

1. Copy tiles byte-identically and verify SHA256. Rewrite main glyph paths.
2. Write the relocated capture manifest with source paths relative to R and
   matching cp/path/SHA entries. Compute SHA256 of these exact capture bytes.
3. Write that SHA into evidence `capture`. Rewrite selected/witness relative
   paths if needed. Preserve style, cohort, frame, immutable K and actual evidence.
4. Compute SHA256 of the final evidence bytes.
5. In main, set `capture_manifest FILE CAPTURE_SHA` and
   `notdef evidence FILE EVIDENCE_SHA STYLE CAPTURE_SHA SCALE FRAME`.

CAPTURE is verified: it is the independent capture manifest SHA256, not a hash
of the main manifest. `notdef_caller::load` verifies capture bytes against its
main-manifest pin, passes that pin into `RunIdentity`, and the validator compares
both binding CAPTURE and evidence `capture` to it. Main manifest is not part of
this hash dependency, so there is no circular hash.

If an entire bundle moves with unchanged relative paths and byte contents,
capture/evidence pins stay unchanged. Only the new manifest base and its resolved
paths change. A relocation must not replace real capture evidence with placeholders.

Failure names: external/non-contained/parent traversal gives ContextMismatch;
cp/path inventory disagreement gives AuditMismatch; altered pinned bytes gives
ShaMismatch. No fitting or output publication is needed to test this contract.
