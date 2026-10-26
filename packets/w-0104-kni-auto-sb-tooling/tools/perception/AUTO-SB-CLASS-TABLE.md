# AUTO-SB vector class table

Card 20261024-010-kni. This is a conservative measurement tool and a measured
historical-font table, not a production-ready classifier or a production gate.
No engine behavior, pool selection, thresholds in the engine or production font
is changed. Existing draft classes OPEN/OVERHANG/serif semantics are unresolved.

## Run

Requires Python 3 and fontTools (tested with 4.65.0):

```
python3 tools/perception/auto_sb_class_table.py FONT.otf NEW-TABLE.tsv --min-flat-em 0.30
python3 -m unittest discover -s tools/perception/tests -p 'test_auto_sb_class_table.py' -v
```

The threshold is mandatory and explicitly provisional. 0.30 comes from the
existing draft, not a ratified production value. Output uses exclusive creation;
an existing table is never overwritten. The receipt printed to stdout binds the
same input bytes parsed by TTFont and the exact output bytes. It reports row and
side counts separately. One font supplies all geometry; there is no foreign pool.

The thirteen-column table matches the existing engine loader's positional
contract: glyph at column 1, classes at columns 6 and 7. Class IDs are flat_stem,
round, empty, unclassified. No Unicode name/category heuristic assigns geometry.
BasePen decomposes components and implied quadratic on-curve points. Bounds and
extrema are computed from vector curves, not raster samples or polygon flattening.
All contours are included. Open contours refuse instead of silently closing.

FLAT requires a vertical line segment at the extreme reaching the explicit em
threshold. ROUND requires a Bezier extreme with a vertical tangent (interior or
endpoint), without a competing vertical flat or oblique line at that extreme.
This describes measured edge geometry, not optical intent. All other cases stay
UNCLASSIFIED. Empty is represented as the existing loader's class-less token.

Do not map unclassified to empty or silently assign it a global median. The
current engine can use global fallback for empty/class-less entries; this tool
does not revise that behavior. Do not feed this table into an owner-bound font
without a separately reviewed pool/coverage/glyph-ID binding and visual gate.

## Measured sample, not the current engine output

Input committed at base 421cc5d875bb082587dbaf69964e65a9d73a157b:
chief-state/plans/auto-sb-mode/r4-mercator/off-run/font-Mercator-Regular.otf

SHA256 1ca1866d77eca1e9412a0d3939d22f645fc63551fcb836e5674c751561f1d32c.
The sample is historical and is not asserted to match a current pipeline build.
83 glyph rows, 166 sides: empty 4, flat_stem 1, round 36, unclassified 125.
Two independent invocations produced identical table bytes:
9907972963187d8d5e382d688f305007d0910baa06334270241449fa7c0cc386.

Sample files: fixtures/auto-sb-mercator/class-table.tsv and receipt.json.
The unresolved 125 sides are a measured coverage limit, not success. Many traced
outlines consist of small curves rather than exact long stems, so this strict
first measurement deliberately declines to manufacture a broad flat class.

## Tests and limits

Nine tests cover flat/round/empty, transformed composite, quadratic all-offcurve
implied points, cubic interior extrema, diagonal ambiguity, open contour refusal,
invalid thresholds, deterministic bytes and consumer column positions. The named
combined fixture test checks several geometries, not six independent fonts.

No full Rust engine suite, font rewrite, OTF generation, production integration,
visual quality gate or pool-median application was run. The tests do not prove
optical classification quality. Next: review unclassified edge measurements on
the actual selected font, define and verify missing classes without category
shortcuts, bind actual solved glyph IDs and pool provenance, then run the existing
ON/OFF visual gate. A table alone is not production acceptance.

## Identity-binding follow-up

`auto_sb_binding_audit.py FONT TABLE MANIFEST RECEIPT` prints a read-only JSON
identity/coverage audit. The committed sample `binding-audit.json` binds all four
input byte hashes. On the historical sample: 81 manifest glyphs = 81 receipt
glyphs; all are in the 83-row font/table, with only .notdef and space extra.
Manifest SHA256 eeced52c769c9f7bb2eff77b641308e585f20916d4bb4ba0dcbf5a56ba15101b
matches the receipt's manifest_pin. Receipt SHA256:
42d3b47ff2238bd22974e51119709d874a4de8c4e6d945d5615bfa5e00f72e79.

The receipt explicitly reports partial_output for missing gid0 evidence and
spacing_solution_incomplete, and spacing complete=false. Generic `fallback`
rows report geometry line-span counts: they do NOT prove fallback_unsolved
membership. Neither matching glyph names nor these rows authenticate the actual
A2 solved population or bind this OTF to its execution. Both remain UNMAPPED.
No pool file is created. No bearings are projected from hmtx as solver truth.

The earlier v03 prototype diagnosis at
chief-state/plans/auto-sb-mode/w-a3-edge-class/v03/edge-class-v03-diagnosis-292c002a.md
has no real-font ground-truth accuracy claim and documents component/window
tradeoffs. It cannot supply missing production semantics or ratify thresholds.

Concrete separable remaining work:
1. Obtain a coherent selected solved-font/receipt/source set with explicit A2
   eligible glyph identity and units/pool provenance; validate identity before
   deriving any median observations. Historical sample equality is not that gate.
2. Measure the unresolved sides and define missing OPEN/OVERHANG/serif semantics
   against actual outlines; no category shortcuts or threshold changes to force
   classification. Review independent labels before any accuracy claim.
3. Bind the validated table and same-scale population to the engine on a branch,
   then run ON/OFF and visual gates. Do not reuse the partial historical sample
   as a production acceptance result.
