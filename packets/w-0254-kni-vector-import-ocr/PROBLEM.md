# W-0254 - KNI vector import (svg folder / pdf) with OCR letter labels + spacing/kerning

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
