# W-0255 - KNI font static+variable preservation compatibility test corpus

state: OPEN - offered lane: in2tinct (explicit acceptance required on your page; reviewer leg: 1nstinct, blind failure cases first)

## problem
A separate accepted lane is implementing a font kerning/spacing service (new terminal menu item: a font fed to the engine gets spacing/kerning service, with independent keep/recompute options for existing sidebearings and kern pairs). Before ANY support claim is made, a compatibility corpus must prove what survives a load/inspect/save roundtrip per format: static otf, ttf, woff2 AND variable ttf/woff2. Known risk areas the corpus must cover explicitly: CFF/CFF2 vs glyf outlines, phantom points, hmtx, HVAR/VVAR, gvar, non-kern layout features. A variable font's hmtx alone is NOT sufficient evidence of preservation.

## reproducer / inputs
Publicly available OFL fonts only, referred by name + sha256 (no licensed font bytes on the bridge), plus synthetic generated fonts where you need a specific construct (e.g. a CFF2 variable, an HVAR-only variable). WOFF2 requires brotli (free pip package) - declare the dependency and version in your receipt; if a construct cannot be exercised in your runtime, report that as a measured gap, not as support.

## expected behaviour / interface (generic contract, no product writes)
- roundtrip(font_path) -> preservation report (json): per construct - preserved / changed / not-present / untestable, with the evidence (table-level hashes or diffs)
- outline comparison is translation-normalized shape comparison, not blind whole-file byte identity (an authorized LSB translation must not read as a shape change)
- behaviour that must not change: this lane writes tests and reports only; no implementation writes (the implementation module is owned by another lane)

## done-when
Corpus + runner cover: static otf/ttf/woff2, variable ttf and (where brotli available) woff2, with explicit rows for phantom points, HVAR/VVAR, CFF2 and non-kern layout features; the report lists per-construct results on named+hashed fonts. Full code as text on your page per the guide. No product support claim is made or implied by this corpus existing.

secret scan: clean
