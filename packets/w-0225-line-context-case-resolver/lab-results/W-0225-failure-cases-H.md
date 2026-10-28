# W-0225 reviewer failure cases (in2tinct, written before reading any solver fix)

Basis: only packet W-0225.md at bridge commit e7c61a2d. No 1nstinct code, output or peer message read. Status: proposed reviewer checks and open questions, not packet acceptance criteria. Only items marked PACKET come from the packet text. Everything else is an exploratory stress test or a question for the solver/owner. Deadline: the packet text (W-0225.md at e7c61a2d) states no deadline; it only says posted 2026-10-28 Europe/Istanbul and one W id for its whole life. Packet acceptance (supplied safety tests pass, single-glyph line unresolved, calibration-only design, validation judged once, sealed test cohorts used once after freeze) is listed separately at the end.

Signature: resolve_line_case(regions, line=None) -> list of {label, ratio, reason}. Hint is geometric only.

## A. Abstention cases (A1-A5 PACKET-mandated where marked; rest exploratory)
1. PACKET: 1 region and 2 regions (single/two-glyph lines) return unresolved; one-glyph always unresolved. Empty list: proposed, expect empty output or unresolved (question).
2. PACKET (all-same-height lines unresolved; heights not separating into two clusters unresolved): 3+ regions, all ink_h equal (all-caps word, all-lowercase x-height-only word like "ounce", "saw", "zzz").
3. PACKET (no two clusters => unresolved): heights vary continuously (no gap): e.g. 40,44,48,52,56,60.
4. PACKET (rotated/uneven baselines unresolved): rotated or sloped line: box y0 drifts linearly by more than a fraction of ink_h across the line. Uneven baselines (bottoms differ).
5. Exploratory: line given but baseline_y <= top_y, or top_y/baseline_y inconsistent with boxes.
6. Question on invalid-input policy (raise, reject or unresolved is not set by the packet): NaN, inf, zero or negative ink_h, x1<x0, y1<y0, ink_h much larger than box height, ink_h=0 (blank glyph). Ask the solver to document the policy; do not fail a documented choice.
7. Exploratory: duplicate/overlapping boxes, unsorted x order. Proposed invariant: output order matches input order. Observe and record.
8. Exploratory, not mandated: mixed-size line (large title word plus small text) where two clusters come from font size. Geometry alone may not identify this; record what the solver does and whether the reason string is honest. Not a gate.

## B. Identifiability traps (exploratory; PACKET says hints stay geometric and two clusters are not proof of case)
9. Observe: a line of all capitals plus small glyphs (period, comma, hyphen; outside the 62 classes but common in real lines). Geometric labels may honestly group small ink as lower_like by measured height even though the glyph has no case. Record where a reader could take that as a semantic claim; this is not a failure by itself.
10. Observe: "ADAM", "Adam", "aDAM". Check that the reason string stays geometric (relative height) and does not name a letter or say uppercase/lowercase as fact. Whether labels differ is information only.
11. Observe: ascender lowercase (b d f h k l t) can cluster with capitals by height. Descenders (g j p q y) have larger ink_h with bottoms below the baseline, so on a descender-heavy line ("gypsy", "jqpyg") they may be grouped upper_like by height. That is an honest geometric grouping; note the risk of misleading semantic reading. Not a failure.
12. Observe: digits (0-9, in the 62 classes) have cap-height-like heights and may group upper_like. Note whether any text implies they have case.
13. Fonts with small caps, unicase, or very small x-height ratio (x/cap < 0.55) and very large (> 0.8): clusters merge or invert. Check both extremes stay unresolved or correct-geometric.
14. Observe: c/C o/O s/S u/U v/V w/W x/X z/Z p/P adjacent in one line. Check that labels derive from relative height within the line and the output names no letter (the packet requires no letter and no Unicode).

## C. Cluster logic (proposed semantics and questions unless noted)
15. Measure scale and quantization sensitivity: the same line at 256/384/512 px, and +-1 px ink_h noise, including a gap at the threshold. Report how labels and ratio change. Whether labels stay stable is a question for the solver, not a requirement.
16. Single outlier: one tall glyph in 8 equal ones (e.g. "wwwwwwwT"): ask what minimum support is used (packet says only 'too few neighbours'); a one-sample cluster being upper_like by default would be worth noting.
17. Observe: three height groups (lower, ascender, cap). Check and record how they are handled (forced into two, partly unresolved, or other) and whether the reason says so. Packet only requires unresolved when heights do not separate into two clusters.
18. Ratio semantics: packet says float|None and 'with the measured ratio'. Question: is ratio None for unresolved, finite and in a stated range otherwise; documented which over which (small/large or region/cluster).
19. Determinism: same input twice, input list permuted (with output permuted back), shuffled dict key order give identical results. Input regions not mutated.
20. Types: ints vs floats vs numpy scalars; numpy-only, no network, no weights, no file writes (import check).

## D. Harness and evaluation failure modes (PACKET items marked; rest are proposed diagnostics)
21. PACKET: leakage: thresholds fit on calibration families only; check config diff shows no value changed after validation was run; validation run count is one.
22. PACKET: sealed cohorts (baseline test5 and added24): zero use before freeze; one final descriptive run; record freeze commit before it.
23. Tight-crop: PACKET says heights come from the page before tight cropping. Test that the original relative ink scale is retained at the resolver input (for example recorded pre-crop dimensions or page-level boxes). A cropped representation can still keep geometry if pre-crop dimensions are recorded; do not assume every cropped form loses scale. Check where ink_h in the harness comes from.
24. PACKET: render-case labels in the harness (known lower/upper) are for descriptive association only; if reported as "accuracy", reject. Fixture/oracle results claim no recognizer accuracy.
25. PACKET: per-family reporting: abstention rate and grouping rate per family; whole-family bootstrap intervals (resample families, not lines); with 5 families intervals will be wide, state that. Do not pool lines across families to shrink intervals.
26. Proposed: report by line type (mixed, all-lower, all-upper, single/two-glyph, descender-heavy), not only overall; an overall abstention rate hides all-caps lines being resolved wrongly.
27. Proposed diagnostic, not acceptance: an always-unresolved resolver would pass abstention-style safety tests, so report the resolved share on mixed-height lines (calibration and validation) as information; a low share is not a failure by itself. Also report a proposed consistency count: regions labeled lower_like whose measured ink is taller than a region labeled upper_like in the same line (expected 0 as an invariant to inspect).
28. PACKET: delivery: version, start commit, patch, run command and test output under one delivery id (123e). Any code change after results invalidates them. Secret scan line, no font bytes, no weights.

## Packet acceptance (from the packet, not reviewer additions)
- Supplied pure-geometry safety tests pass (they do not prove case).
- OFL synthetic-line harness: mixed heights, all-lower x-height-only, all-upper, single/two glyphs, descender-heavy.
- Calibration-only design; validation judged once; sealed cohorts used once after freeze.
- Per-family grouping/abstention, whole-family bootstrap intervals, separate descriptive association with render-case labels.
- One-glyph line always unresolved; no letter, no Unicode.
