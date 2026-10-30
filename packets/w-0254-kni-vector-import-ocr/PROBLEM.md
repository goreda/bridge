# W-0254 - KNI vector import (svg folder / pdf) with OCR letter labels + spacing/kerning

## v2 amendment (2026-10-30 16:28 Europe/Istanbul, owner block 162c) - LANE REASSIGNMENT

The lane split changed by owner direction: the SOLVER leg of this vector/512 packet moves to in2tinct; the blind REVIEWER leg moves to 1nstinct (failure cases frozen before reading solver conclusions). 1nstinct's earlier solver acceptance (G-0509) is superseded and released - with thanks, no penalty; the review leg is its lane now. in2tinct: this packet is offered to you as solver - an EXPLICIT acceptance line on your own page is required; nothing is assumed from silence. Added scope from 162c: raster fallback ONLY when a pdf has no vectors; grouping paths into letters; scale to units-per-em; baseline from the page. Licence rule (162d): until the owner's licence word, lab results enter the product as specs, failing tests and reference algorithms implemented by the integrators - keep delivering code as text on your page per the guide. The rest of this packet stands. secret scan: clean

state: OPEN - offered lane: 1nstinct (explicit acceptance required on your page; reviewer leg: in2tinct, blind failure cases first)

## problem
The product needs a NEW menu option (separate from the font kerning/spacing service): given vector input - a folder of SVG drawings or a PDF page holding several distinct letter drawings (example shape: 6-9 different letters on one page) - the engine must take each drawing EXACTLY as drawn (no redraw, no re-vectorization, no cleanup that changes the shape), recognize which letter each drawing is, and compute spacing (sidebearings) and kerning for the set, then output the result. Today this import route does not exist.

## reproducer / inputs
Self-contained: build a synthetic public test set (6-9 distinct letter drawings as one SVG folder and one equivalent PDF page; simple sans-like outlines are fine, geometry you author yourself or OFL/public-domain sources referred by name + sha256 only - no licensed fonts, no captures). The set must include at least one letter whose identity is ambiguous on purpose, to prove abstention.

## expected behaviour / interface (generic contract, integration wiring is a reserved separate lane)
- import_vectors(input: svg-dir-path | pdf-path) -> glyphs: [{id, label or ABSTAIN, outline}], plus a report (per-glyph decision + reason)
- compute_metrics(glyphs) -> {lsb, rsb per glyph; kern pairs for the set}
- drawings are preserved: translation-normalized outline shape identical to the input (translation for an authorized LSB placement is allowed; the SHAPE is what is preserved - not blind byte identity of a whole file)
- recognition is typed/abstaining: an uncertain glyph is ABSTAIN, never a confident wrong label
- behaviour that must not change: input files are never modified; no font-format writes in this lane

## done-when
On your published synthetic set: every glyph either correctly labeled or abstained (zero wrong accepts), outline preservation verified per glyph (translation-normalized comparison), spacing/kerning output produced and shown. Result format per the guide: what was done, numbers, full code as text, what is not done or not measured. Acceptance remains the owner's eyes; this is a module + tests, not product integration.

secret scan: clean

## v2 failing-input fixtures (hand-authored synthetic, public-shareable, no licensed or private font data; requesting-side measurements against the CURRENT unsafe private skeleton - they show what your module must get right)

- fixtures/pub-block-letters.svg - basic multi-letter page (control)
- fixtures/pub-clip-transform.svg - clip + transformed paths: the current extractor loses 60pt of geometry here
- fixtures/pub-nonzero-overlap.svg - nonzero fill-rule compound ring/arc: .898pt deviation observed
- fixtures/pub-multirow.svg - multi-row page: x-only grouping over-merges rows
- fixtures/verification-v3.txt - the actual commands + outputs behind those numbers

Pins:
- fixtures/pub-block-letters.svg sha256 1433dee10189b87157ef18fbd0e45cc7405d8b5088e8c36bef943e96663c8ff3 562B
- fixtures/pub-clip-transform.svg sha256 d7a071a02a0558d96faa0434282ba452c3a13b44687c91a1093fcbec348fd621 582B
- fixtures/pub-multirow.svg sha256 7ec48560b8cb082e557e2462d49aafbc4be00916825142a99bd5ee3d3fb20555 555B
- fixtures/pub-nonzero-overlap.svg sha256 f3306c3bc6c7794875bcad97193a82d02d20d4c4a57526822a813a30ac5b922d 308B
- fixtures/verification-v3.txt sha256 febefab0e466f7f534364ca1afbd223466ba1273fe6e35315cfd12d74d2600cd 2279B
Expectation: your module preserves the original path geometry (translation-normalized), honors fill rule and transforms, records clips/unsupported items as typed gaps, and separates rows/groups correctly on these inputs. secret scan: clean
